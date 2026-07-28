import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §8.4, specs/009-device-runtime.md §5.4 — a thin delegate onto
/// `GeofenceConfigSyncCoordinator.sync()`. The push payload's own `etag` field is informational
/// only; the coordinator's cached ETag (via `If-None-Match`) is the actual source of truth, so the
/// handler ignores the payload entirely, exactly like Android's `GeofenceConfigChangedPushHandler`.
///
/// **I11 reconciliation:** `GeofenceConfigSyncCoordinator` is now I11's real
/// `LocationSensing/GeofenceConfigSyncCoordinator.swift` (fetch/cache/full-replace-register,
/// specs/009 §6.2) — I12's own placeholder trio (`GeofenceConfigCaching`/`GeofenceConfigRegistering`/
/// a same-named stub coordinator) was deleted once I11 landed the real thing with the identical
/// `sync()` shape this handler already called, so `handle`'s body needed zero changes. The
/// coordinator's own full behavior (ETag handling, the 000 §O9 20-region cap, `syncIfEtagChanged`,
/// …) is covered by I11's own `LocationSensing/GeofenceConfigSyncCoordinatorTests.swift`; this file
/// only tests that the handler delegates to it.
struct GeofenceConfigChangedPushHandlerTests {

    @Test func handle_delegatesToTheSyncCoordinator() async {
        let api = FakeAPIClient()
        let config = GeofenceConfig(version: 1, geofences: [])
        api.getGeofencesHandler = { _ in .ok(config, etag: "\"e1\"", features: TestFeatures.free) }
        let store = InMemoryGeofenceConfigStateStore()
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)
        let handler = GeofenceConfigChangedPushHandler(syncCoordinator: coordinator)

        await handler.handle(["type": "GEOFENCE_CONFIG_CHANGED", "etag": "\"e1\""])

        #expect(api.getGeofencesCalls.count == 1)
        #expect(store.current() == CachedGeofenceConfig(etag: "\"e1\"", geofences: []))
        #expect(registrar.registerAllCalls.count == 1)
    }
}
