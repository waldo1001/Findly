import Foundation

/// **I11's not-yet-built full re-registration seam** (specs/009-device-runtime.md §6.2's "register
/// all" half — the complement to `GeofenceRegistrarStub.unregisterAll()`, which is deliberately
/// scoped to unregister-only per its own doc). Stubbed the same way Android's A9 stubbed
/// `GeofenceRegistrar`/`GeofenceRegistrarStub`: a documented no-op default implementation a future
/// I11 session replaces with the real `CLLocationManager` region-monitoring register-all call (full
/// unregister-all/register-all replace, capped by the caller at `features.limits.maxGeofences`
/// before this is ever invoked — specs/009 §6.2). `GeofenceConfigSyncCoordinator` is the one
/// caller; do not change this shape without checking it.
public protocol GeofenceConfigRegistering {
    func registerAll(_ geofences: [Geofence]) async
}

public final class NoOpGeofenceConfigRegistering: GeofenceConfigRegistering {
    public init() {}
    public func registerAll(_ geofences: [Geofence]) async {}
}
