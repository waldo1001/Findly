@testable import FindlyKit

/// A recording `GeofenceRegistering` test double — shared across `GeofenceConfigSyncCoordinatorTests`
/// and `LocationRuntimeContainerTests`, mirroring `FakeGeofenceRegistrarStub`'s role for the
/// narrower unregister-only protocol.
final class FakeGeofenceRegistering: GeofenceRegistering {
    private(set) var unregisterAllCallCount = 0
    private(set) var registerAllCalls: [(geofences: [Geofence], etag: String)] = []

    func unregisterAll() {
        unregisterAllCallCount += 1
    }

    func registerAll(geofences: [Geofence], etag: String) {
        registerAllCalls.append((geofences, etag))
    }
}
