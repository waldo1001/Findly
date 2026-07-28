import Foundation
#if os(iOS) && canImport(CoreLocation)
import CoreLocation
#endif

#if os(iOS) && canImport(CoreLocation)
/// The real, `CLLocationManager` region-monitoring-backed `GeofenceRegistering` (specs/009-device-
/// runtime.md §6.2) — one class implements both halves (`unregisterAll`/`registerAll`), mirroring
/// how Android's A11 ended up with one `GeofencingClientManager` implementing both
/// `GeofenceRegistry`/`GeofenceRegistrar`, exactly as A10's own report predicted for iOS too.
///
/// **A dedicated `CLLocationManager` instance, separate from `SystemLocationProvider`'s.** Multiple
/// `CLLocationManager` instances in one process are fully supported (authorization status is
/// app-wide, not per-instance) — keeping region monitoring on its own instance/delegate means this
/// class never touches `SystemLocationProvider`'s already-reviewed single-fix/significant-location-
/// change code at all, zero regression risk to I10's work.
///
/// Registration is always a full replace, "unregister all, then register all", performed
/// synchronously inside `registerAll` itself (unlike Android's `GeofencingClientManager`, no
/// `Task`/coroutine dance is needed — `CLLocationManager.startMonitoring(for:)`/`stopMonitoring(for:)`
/// are synchronous, fire-and-forget calls with no completion handshake). **Non-atomicity is
/// accepted, not a bug** (specs/009 §6.2, normative) — if the process dies mid-replace, the device
/// is left with zero geofences registered, a real, reachable, self-healing state (the next
/// `geofenceEtag` mismatch re-triggers a full retry via `GeofenceConfigSyncCoordinator`). No
/// retry/transaction logic is attempted here to "fix" that.
///
/// Defensively re-clamps to `GeofenceConfigSyncCoordinator.platformRegionCap` (20) even though its
/// only production caller already caps there first (000 §O9's 20-region-per-app ceiling) — cheap
/// insurance against `CLLocationManager` silently failing to monitor a region past the 20th (via
/// `monitoringDidFailFor`) if some future caller ever passes more.
///
/// Permission-gated per specs/009 §7 (mirrors how `FixCaptureCoordinator` checks
/// `isPermissionGranted` before capturing, and the A11 task brief's explicit instruction not to
/// just let `CLLocationManager` silently no-op): `startMonitoring(for:)` is skipped entirely when
/// at least When-In-Use authorization isn't currently granted. `unregisterAll` has no such gate —
/// removing a registration is always safe to attempt regardless of current permission state.
/// Does NOT itself request authorization (`SystemLocationProvider`'s `init`/
/// `requestAlwaysAuthorizationUpgrade()` already own that staged When-In-Use → Always flow, specs/
/// 009 §7) — duplicating a request here would risk a second, redundant system prompt.
///
/// Thin, untested Android-framework-equivalent glue by design (same bucket as `SystemLocationProvider`
/// itself) — all cap/cache/ETag decision logic lives in the tested `GeofenceConfigSyncCoordinator`,
/// this class's one caller for `registerAll`. `transitionHandler` is `weak` and settable
/// post-construction — mirrors `SystemLocationProvider.backgroundCoordinator`'s pattern exactly,
/// for the identical reason: this class is built in `FindlyApp.init()` BEFORE
/// `LocationRuntimeContainer` (and therefore `GeofenceTransitionHandler`) exists yet.
public final class SystemGeofenceRegistrar: NSObject, GeofenceRegistering {
    private let manager: CLLocationManager

    /// Set once, after `LocationRuntimeContainer` is constructed (see class doc). `weak` so this
    /// registrar never keeps the container's handler graph alive past its own owner's lifetime.
    public weak var transitionHandler: GeofenceTransitionHandling?

    public override init() {
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    public var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        case .notDetermined, .denied, .restricted: return false
        @unknown default: return false
        }
    }

    public func unregisterAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }

    public func registerAll(geofences: [Geofence], etag: String) {
        unregisterAll()
        guard !geofences.isEmpty else { return }
        guard isAuthorized else { return }
        for geofence in geofences.prefix(GeofenceConfigSyncCoordinator.platformRegionCap) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: geofence.lat, longitude: geofence.lon),
                radius: geofence.radiusM,
                identifier: geofence.geofenceId
            )
            // specs/009 §6.2: "Devices MUST register and report all transitions regardless of the
            // notifyOnEnter/notifyOnExit flags" - those control server-side fan-out only (001 §7.1).
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }
}

extension SystemGeofenceRegistrar: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        forwardTransition(region: region, transition: .enter)
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        forwardTransition(region: region, transition: .exit)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // specs/009 §9: never log coordinates/deviceId/tokens - a monitoring failure for one
        // region (e.g. the 21st past the platform cap, or a malformed region) is swallowed here;
        // the next full re-registration (§6.2's triggers) retries from a clean slate.
    }

    /// `CLCircularRegion`'s own `center`/`radius` are the best available proxy for "the
    /// transition's own coordinates" on iOS (specs/009 §6.3: "MAY reuse the transition's own
    /// coordinates") — unlike Android's `GeofencingEvent.triggeringLocation`, CoreLocation's
    /// region-monitoring delegate callbacks carry no location of their own. `manager.location`
    /// (the location manager's own last-known fix, when CoreLocation happens to have one cached) is
    /// preferred when available since it is an actual GPS observation rather than the region's
    /// static center — a documented, judgment-call interpretation of "MAY reuse" for a platform
    /// that doesn't hand back a triggering location the way Android does.
    private func forwardTransition(region: CLRegion, transition: GeofenceTransition) {
        guard let circular = region as? CLCircularRegion else { return }
        let coordinate = manager.location?.coordinate ?? circular.center
        let accuracyM = manager.location.map { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : circular.radius } ?? circular.radius
        let event = GeofenceTransitionEvent(
            geofenceId: circular.identifier, transition: transition,
            lat: coordinate.latitude, lon: coordinate.longitude, accuracyM: accuracyM
        )
        Task { [weak transitionHandler] in
            await transitionHandler?.handle(event)
        }
    }
}
#endif
