import Foundation
#if os(iOS) && canImport(CoreLocation)
import CoreLocation
#endif

/// specs/004-ios-client.md §7, specs/009-device-runtime.md §1/§7 — foreground single-fix capture
/// (accuracy/timeout per §1.1's table, via `FixAccuracyPolicy`) + background
/// significant-location-change monitoring, behind a protocol so `FixCaptureCoordinator`/
/// `DeviceRegistrationService` consumers stay testable without CoreLocation.
///
/// **I10 widening from I1's scaffolding shape** (`requestSingleFix() async throws -> LocationFix`,
/// `startBackgroundMonitoring(into: FixQueue)`):
///
/// - `requestSingleFix(source:)` now takes the `FixSource` that's driving the request, so the
///   accuracy tier + timeout (specs/009 §1.1) are derived from a single seam every future caller
///   (I11's geofence trigger, I12's `LOCATE_REQUEST` handler) goes through, rather than each
///   re-deriving the mapping. `source: .locate` deliberately bypasses `FixCaptureCoordinator`
///   (mirrors Android's `LocateRequestPushHandler` calling `LocationCapturer` directly) — a
///   `LOCATE_REQUEST` MUST still be fulfilled while paused (009 §5.1), which this protocol method
///   alone correctly allows (no suppression baked in here) but `FixCaptureCoordinator` correctly
///   forbids for `periodic`/`manual`/`geofence`.
/// - `startBackgroundMonitoring` now takes the pure `FixCaptureCoordinator` (not a raw `FixQueue`)
///   so significant-location-change callbacks go through the SAME §1.2 suppression rules
///   (paused / permission-absent / <60 s debounce) as every other capture trigger — wiring
///   straight to `FixQueue.enqueue` would silently bypass all three. Each SLC callback's own
///   coordinates are passed as `hint:` (specs/009 §6.3's "MAY reuse the transition's own
///   coordinates" pattern, applied here to significant-location-change too — no reason to spend a
///   second GPS request when the OS already handed us a location).
public protocol LocationProviding: AnyObject {
    func requestSingleFix(source: FixSource) async throws -> LocationFix
    func startBackgroundMonitoring(coordinator: FixCaptureCoordinator)
    func stopBackgroundMonitoring()

    /// Current authorization, collapsed to the four states `PermissionFlowPolicy` reasons about
    /// (specs/009 §7). Distinct from the pre-existing `isAuthorized`, which answers "can I capture
    /// a fix right now?" and cannot distinguish *not yet asked* from *refused* — a distinction the
    /// disclosure flow depends on, since only one of those two can still be prompted.
    var authorization: LocationAuthorization { get }
}

public extension LocationProviding {
    /// Defaults to `.notDetermined` so the many test fakes and the macOS/no-op provider need no
    /// change; only the real CoreLocation-backed provider reports a meaningful value.
    var authorization: LocationAuthorization { .notDetermined }
}

/// The two OS prompts, behind a protocol so `LocationRuntimeContainer` can trigger them without
/// importing CoreLocation or knowing which concrete provider it holds — and so a test double can
/// stand in on macOS, where `SystemLocationProvider` does not exist at all.
public extension Notification.Name {
    /// Posted when CoreLocation reports an authorization change (specs/009 §7). Answering the OS
    /// dialog does **not** move the app through a scene-phase change, so the foreground re-check
    /// alone would leave the banner and the deferred monitoring stale until the user next left and
    /// returned. This is the signal that closes that gap.
    static let findlyLocationAuthorizationChanged = Notification.Name("com.findly.locationAuthorizationChanged")
}

public protocol SystemLocationProviderRequesting: AnyObject {
    /// MUST be called only after the foreground disclosure is acknowledged (specs/009 §7).
    func requestWhenInUseAuthorizationIfNeeded()
    /// MUST be called only after the background disclosure is acknowledged (003 §11.2).
    func requestAlwaysAuthorizationUpgrade()
}

public enum LocationProvidingError: Error, Equatable {
    case notImplemented
    case timedOut
    case permissionDenied
    /// A CoreLocation failure whose description is safe to carry (never coordinates/deviceId —
    /// docs/security-review-checklist.md); callers log `.localizedDescription` of this case only,
    /// never the underlying `CLError` object.
    case underlying(String)
}

/// Test/macOS-build default — always fails `requestSingleFix`, background monitoring is inert.
public final class NoOpLocationProvider: LocationProviding {
    public init() {}
    public func requestSingleFix(source: FixSource) async throws -> LocationFix { throw LocationProvidingError.notImplemented }
    public func startBackgroundMonitoring(coordinator: FixCaptureCoordinator) {}
    public func stopBackgroundMonitoring() {}
}

#if os(iOS) && canImport(CoreLocation)
/// The real on-device implementation (specs/009 §1, §3.4, §7). Thin, CoreLocation-touching glue
/// by design — the module layout table (specs/004 §1.2) calls this out explicitly ("real GPS/BG
/// wiring is a runtime TODO"); I10 is that runtime session. All suppression/accuracy-tier logic
/// lives elsewhere (`FixCaptureCoordinator`, `FixAccuracyPolicy`) so this class stays a pure
/// CLLocationManager adapter, unit-untestable by nature (same bucket as Android's
/// `FusedLocationCapturer`) but kept as small as possible so there's little here to get wrong.
public final class SystemLocationProvider: NSObject, LocationProviding, SystemLocationProviderRequesting {
    private let manager: CLLocationManager
    private let batteryLevelProvider: () -> Int

    /// specs/009 §3.4 (I50 fix 5) — every in-flight `requestSingleFix` caller, keyed and resumed
    /// independently so a second concurrent caller (I52's presence timer, I51's `LOCATE_REQUEST`
    /// handler, and the opportunistic BG-refresh trigger can all call this concurrently) resumes
    /// exactly once instead of silently overwriting — and leaking — an earlier caller's
    /// continuation. See `PendingFixContinuations`'s own doc for the full rationale.
    private let pendingFixes = PendingFixContinuations()

    /// The coordinator background monitoring hands significant-location-change/visit callbacks
    /// to — set once by `startBackgroundMonitoring(coordinator:)`, cleared by
    /// `stopBackgroundMonitoring()`.
    private weak var backgroundCoordinator: FixCaptureCoordinator?

    /// `batteryLevelProvider` is injected (not read from `UIDevice` directly) so this class stays
    /// constructible — if not fully testable — outside a real device context; the real app target
    /// wiring passes `{ Int(UIDevice.current.batteryLevel * 100) }` after enabling
    /// `UIDevice.current.isBatteryMonitoringEnabled`.
    public init(batteryLevelProvider: @escaping () -> Int = { 100 }) {
        self.manager = CLLocationManager()
        self.batteryLevelProvider = batteryLevelProvider
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // specs/009 §7 / specs/004 §7: When-In-Use first, then a deliberate Always upgrade — each
        // shown only AFTER its in-app explanation.
        //
        // **This initializer used to call `requestWhenInUseAuthorization()` directly**, which meant
        // the OS dialog appeared the instant the location stack was constructed, before the user
        // had been told anything. That is the precise inversion §7 forbids ("a prominent disclosure
        // precedes the OS prompt") and the thing Play's background-location review checks. It was
        // written when no screen existed to host the explanation; `PermissionDisclosureScreen` now
        // does, and `PermissionFlowViewModel` owns the ordering. Prompting is therefore an explicit
        // call — never a side effect of construction.
    }

    /// Fires the When-In-Use prompt. **Call only after the foreground disclosure is acknowledged**
    /// — `PermissionFlowViewModel` is what guarantees that, and its tests are what prove it.
    /// A no-op unless the status is still `.notDetermined`: once the user has answered, iOS will
    /// not show the dialog again, and asking is a wasted delegate round-trip.
    public func requestWhenInUseAuthorizationIfNeeded() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// specs/009 §7's deliberate Always-upgrade prompt — call only after showing the in-app
    /// explanation of family/group background tracking. A no-op if already authorized for Always,
    /// denied, or restricted (CoreLocation itself is a no-op in those cases too; this early-return
    /// just avoids an unnecessary delegate round-trip).
    public func requestAlwaysAuthorizationUpgrade() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    /// specs/009 §7 — the four states the disclosure flow reasons about. `.restricted` maps to
    /// `.denied`: the effect is identical (no location, and no dialog that could change it), and
    /// the banner's "open settings" route is the right advice for both.
    public var authorization: LocationAuthorization {
        switch manager.authorizationStatus {
        case .authorizedAlways: return .always
        case .authorizedWhenInUse: return .whenInUse
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    public var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        case .notDetermined, .denied, .restricted: return false
        @unknown default: return false
        }
    }

    public func requestSingleFix(source: FixSource) async throws -> LocationFix {
        // specs/009 §7: "Permission MUST be re-checked on every capture attempt." No GPS burn at
        // all if we already know it will fail.
        guard isAuthorized else { throw LocationProvidingError.permissionDenied }

        manager.desiredAccuracy = Self.clAccuracy(for: FixAccuracyPolicy.tier(for: source))
        return try await awaitNextLocation(source: source)
    }

    /// Bridges `CLLocationManagerDelegate`'s callback-based `requestLocation()` to `async/await`
    /// via a checked continuation, registered in `pendingFixes` (specs/009 §3.4, I50 fix 5) rather
    /// than a single property. `CLLocationManager.requestLocation()` itself is called only when
    /// this is the FIRST currently-pending caller (`isFirst`) — CoreLocation permits only one
    /// in-flight request; a caller joining an already-in-flight one rides along and is resumed by
    /// the same eventual delegate callback via `pendingFixes.resumeAll`, at no extra GPS cost.
    /// Each call schedules its OWN independent timeout (its `FixAccuracyPolicy` tier's own value —
    /// `geofence`'s 15 s vs. everything else's 30 s), so one caller giving up does not disturb any
    /// other concurrently-pending caller (specs/009 §1.1: "no fix is better than a burned
    /// battery" — applies per caller, not globally).
    private func awaitNextLocation(source: FixSource) async throws -> LocationFix {
        let timeout = FixAccuracyPolicy.timeout(for: source)
        return try await withCheckedThrowingContinuation { continuation in
            let (id, isFirst) = pendingFixes.register(source: source, continuation: continuation)
            if isFirst {
                manager.requestLocation()
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.pendingFixes.timeOut(id: id, error: LocationProvidingError.timedOut)
            }
        }
    }

    public func startBackgroundMonitoring(coordinator: FixCaptureCoordinator) {
        backgroundCoordinator = coordinator
        // specs/009 §3.4 (I50 fix 3, amended 2026-09-06): significant-location-change monitoring
        // and visit monitoring (§3.4's second cheap wake) both need Always — When-In-Use cannot
        // wake a suspended app, so starting either earlier only misleads the permission banner
        // logic. Previously gated on `isAuthorized` (whenInUse-or-always).
        guard BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: authorization) else { return }
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }

    public func stopBackgroundMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        backgroundCoordinator = nil
    }

    private static func clAccuracy(for tier: LocationAccuracyTier) -> CLLocationAccuracy {
        switch tier {
        case .balanced: return kCLLocationAccuracyHundredMeters
        case .high: return kCLLocationAccuracyBest
        }
    }
}

extension SystemLocationProvider: CLLocationManagerDelegate {
    /// specs/009 §7/§3.4 — the app must notice authorization changes without waiting for a
    /// foreground cycle. Fires when the user answers the dialog, and again if they change the
    /// setting in system Settings and return. Carries no location data, so the notification is
    /// safe to broadcast (docs/security-review-checklist.md).
    ///
    /// **I50 fix 1** — also applies `allowsBackgroundLocationUpdates` here, not just once at
    /// construction: it MUST be `true` exactly while authorization is Always and `false`
    /// otherwise (specs/009 §3.4 "Background delivery of one-shot requests" — the root cause of
    /// every silent iOS background capture, since the property defaults to `false` and
    /// CoreLocation withholds standard-service `requestLocation()` delivery in the background
    /// without it). Reacting here, not just once, is what keeps it correct when authorization
    /// drops below Always later (e.g. the user revokes it from system Settings).
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        applyBackgroundLocationUpdatesPolicy()
        NotificationCenter.default.post(name: .findlyLocationAuthorizationChanged, object: nil)
    }

    /// specs/009 §3.4 (I50 fix 1). Setting this without the `location` `UIBackgroundModes` entry
    /// or the Always permission is a CoreLocation runtime error — both preconditions hold here:
    /// `Findly/Info.plist` already declares the `location` background mode, and
    /// `BackgroundLocationPolicy.allowsBackgroundLocationUpdates` only ever returns `true` for
    /// `.always`.
    private func applyBackgroundLocationUpdatesPolicy() {
        manager.allowsBackgroundLocationUpdates = BackgroundLocationPolicy.allowsBackgroundLocationUpdates(for: authorization)
        manager.showsBackgroundLocationIndicator = false
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // specs/009 §3.4 (I50 fix 5) — resumes EVERY pending `requestSingleFix` caller (there may
        // be more than one concurrently waiting on this single in-flight `requestLocation()`),
        // each tagged with its own `source`. `resumeAll` reports whether anything was actually
        // resumed so a stray delivery with nobody waiting still falls through to the
        // significant-location-change/visit hint path below.
        let resolvedAPendingFix = pendingFixes.resumeAll { source in
            location.toLocationFix(source: source, batteryPct: self.batteryLevelProvider())
        }
        guard !resolvedAPendingFix else { return }
        // Not a pending single-fix request - this is a significant-location-change delegate
        // callback (or a stray late delivery after every single-fix request already resolved via
        // timeout). Route through the coordinator's own suppression (specs/009 §1.2) as a
        // `.periodic` hint rather than enqueuing directly.
        guard let coordinator = backgroundCoordinator else { return }
        let fix = location.toLocationFix(source: .periodic, batteryPct: batteryLevelProvider())
        Task { await coordinator.captureAndQueue(source: .periodic, hint: fix) }
    }

    /// specs/009 §3.4 (I50 fix 3, amended 2026-09-06) — visit monitoring, the second cheap wake,
    /// "treated exactly like an SLC callback": the OS-supplied location is passed through the same
    /// `FixCaptureCoordinator` path (as a `.periodic` hint, subject to §1.2 suppression) rather
    /// than enqueued directly. `CLVisit.arrivalDate`/`departureDate` are `Date.distantPast`/
    /// `.distantFuture` when unknown (e.g. a departure-only visit, or one still ongoing) — falls
    /// back to `arrivalDate` first, then `departureDate`, then "now", so `recordedAt` is always a
    /// real timestamp.
    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard let coordinator = backgroundCoordinator else { return }
        let timestamp: Date
        if visit.arrivalDate != Date.distantPast {
            timestamp = visit.arrivalDate
        } else if visit.departureDate != Date.distantFuture {
            timestamp = visit.departureDate
        } else {
            timestamp = Date()
        }
        let fix = LocationFix(
            fixId: UUID().uuidString,
            recordedAt: ISO8601DateFormatter().string(from: timestamp),
            lat: visit.coordinate.latitude,
            lon: visit.coordinate.longitude,
            accuracyM: visit.horizontalAccuracy,
            batteryPct: batteryLevelProvider(),
            source: .periodic
        )
        Task { await coordinator.captureAndQueue(source: .periodic, hint: fix) }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // specs/009 §9: never log coordinates/deviceId/tokens - only an error category. Resumes
        // EVERY pending caller (specs/009 §3.4, I50 fix 5) - CoreLocation delivered one failure for
        // however many callers are waiting on the single in-flight request.
        pendingFixes.failAll(with: LocationProvidingError.underlying(String(describing: type(of: error))))
    }
}

private extension CLLocation {
    func toLocationFix(source: FixSource, batteryPct: Int) -> LocationFix {
        LocationFix(
            fixId: UUID().uuidString,
            recordedAt: ISO8601DateFormatter().string(from: timestamp),
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            accuracyM: horizontalAccuracy,
            altitudeM: verticalAccuracy >= 0 ? altitude : nil,
            speedMps: speed >= 0 ? speed : nil,
            bearingDeg: course >= 0 ? course : nil,
            batteryPct: batteryPct,
            source: source
        )
    }
}
#endif
