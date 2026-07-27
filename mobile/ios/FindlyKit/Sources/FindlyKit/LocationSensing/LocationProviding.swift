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
public final class SystemLocationProvider: NSObject, LocationProviding {
    private let manager: CLLocationManager
    private let batteryLevelProvider: () -> Int

    /// One in-flight `requestSingleFix` continuation at a time — CoreLocation's `requestLocation()`
    /// is itself documented as "do not call again until the previous request completes", so a
    /// second concurrent call here would be a caller bug; the guard makes that fail loud (throws)
    /// instead of silently double-resuming a continuation (a runtime crash) or leaking one (a hang).
    private var pendingFixContinuation: CheckedContinuation<LocationFix, Error>?
    private var pendingFixSource: FixSource?

    /// The coordinator background monitoring hands significant-location-change callbacks to — set
    /// once by `startBackgroundMonitoring(coordinator:)`, cleared by `stopBackgroundMonitoring()`.
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
        // specs/009 §7 / specs/004 §7: When-In-Use first; the deliberate Always upgrade prompt is
        // a separate, explicit call (`requestAlwaysAuthorizationUpgrade()` below) — shown only
        // after an in-app explanation, never auto-fired from init. No onboarding screen exists yet
        // in I2's shipped screen inventory to host that explanation (checked: none of
        // `Screens/*/*.swift` references CLLocationManager/authorization), so triggering the
        // upgrade prompt itself is left as a public method for a future UI session to call, per
        // this task's explicit "UI as a later concern" allowance.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// specs/009 §7's deliberate Always-upgrade prompt — call only after showing the in-app
    /// explanation of family/group background tracking. A no-op if already authorized for Always,
    /// denied, or restricted (CoreLocation itself is a no-op in those cases too; this early-return
    /// just avoids an unnecessary delegate round-trip).
    public func requestAlwaysAuthorizationUpgrade() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
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

        let timeout = FixAccuracyPolicy.timeout(for: source)
        manager.desiredAccuracy = Self.clAccuracy(for: FixAccuracyPolicy.tier(for: source))

        return try await withThrowingTaskGroup(of: LocationFix.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw LocationProvidingError.notImplemented }
                return try await self.awaitNextLocation(source: source)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LocationProvidingError.timedOut
            }
            defer { group.cancelAll() }
            do {
                let result = try await group.next()!
                return result
            } catch {
                // specs/009 §1.1: "no fix is better than a burned battery" - give up silently on
                // timeout; a genuine CoreLocation failure still propagates so the caller can log
                // (never a coordinate/deviceId) an error *category*.
                self.failPendingFix(with: error)
                throw error
            }
        }
    }

    /// Bridges `CLLocationManagerDelegate`'s callback-based `requestLocation()` to `async/await`
    /// via a checked continuation. Never leaks/double-resumes: `pendingFixContinuation` is
    /// consumed exactly once by whichever of `locationManager(_:didUpdateLocations:)` /
    /// `locationManager(_:didFailWithError:)` / the timeout race (`failPendingFix`) fires first;
    /// every one of those three paths nils the property out as it resumes.
    private func awaitNextLocation(source: FixSource) async throws -> LocationFix {
        try await withCheckedThrowingContinuation { continuation in
            self.pendingFixContinuation = continuation
            self.pendingFixSource = source
            self.manager.requestLocation()
        }
    }

    /// Called on the timeout race losing (a genuine timeout) or CoreLocation itself failing —
    /// resumes the pending continuation exactly once, a no-op if it already resumed via
    /// `didUpdateLocations`.
    private func failPendingFix(with error: Error) {
        guard let continuation = pendingFixContinuation else { return }
        pendingFixContinuation = nil
        pendingFixSource = nil
        continuation.resume(throwing: error)
    }

    public func startBackgroundMonitoring(coordinator: FixCaptureCoordinator) {
        backgroundCoordinator = coordinator
        guard isAuthorized else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    public func stopBackgroundMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
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
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if let continuation = pendingFixContinuation, let source = pendingFixSource {
            pendingFixContinuation = nil
            pendingFixSource = nil
            continuation.resume(returning: location.toLocationFix(source: source, batteryPct: batteryLevelProvider()))
            return
        }
        // Not a pending single-fix request - this is a significant-location-change delegate
        // callback (or a stray late delivery after the single-fix request already resolved via
        // timeout). Route through the coordinator's own suppression (specs/009 §1.2) as a
        // `.periodic` hint rather than enqueuing directly.
        guard let coordinator = backgroundCoordinator else { return }
        let fix = location.toLocationFix(source: .periodic, batteryPct: batteryLevelProvider())
        Task { await coordinator.captureAndQueue(source: .periodic, hint: fix) }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // specs/009 §9: never log coordinates/deviceId/tokens - only an error category.
        failPendingFix(with: LocationProvidingError.underlying(String(describing: type(of: error))))
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
