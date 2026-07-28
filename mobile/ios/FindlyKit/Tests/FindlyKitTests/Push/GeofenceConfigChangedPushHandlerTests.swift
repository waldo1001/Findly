import Testing
@testable import FindlyKit

private final class FakeGeofenceConfigCaching: GeofenceConfigCaching {
    var etag: String?
    func cachedEtag() -> String? { etag }
    func cache(etag: String) { self.etag = etag }
}

private final class FakeGeofenceConfigRegistering: GeofenceConfigRegistering {
    private(set) var registeredCalls: [[Geofence]] = []
    func registerAll(_ geofences: [Geofence]) async { registeredCalls.append(geofences) }
}

private func makeGeofence(id: String = "gf_home") -> Geofence {
    Geofence(geofenceId: id, name: "Home", lat: 51.0543, lon: 3.7174, radiusM: 150, icon: "home", notifyOnEnter: true, notifyOnExit: true)
}

/// specs/001-api-contract.md §7.1, specs/009-device-runtime.md §6.1/§6.2 — the fetch-cache-register
/// sequence every §6.2 trigger (incl. the `GEOFENCE_CONFIG_CHANGED` push) ends up calling. Full
/// platform re-registration is I11's scope (`GeofenceConfigRegistering`'s doc) — this coordinator
/// only owns the ETag-conditional fetch + handing the result to whatever registrar is plugged in.
struct GeofenceConfigSyncCoordinatorTests {

    @Test func passesTheCachedEtagAsIfNoneMatch() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .notModified }
        let cache = FakeGeofenceConfigCaching()
        cache.etag = "\"abc\""
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, cache: cache, registrar: FakeGeofenceConfigRegistering())

        await coordinator.sync()

        #expect(api.getGeofencesCalls == ["\"abc\""])
    }

    @Test func noCachedEtag_passesNil() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .notModified }
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, cache: FakeGeofenceConfigCaching(), registrar: FakeGeofenceConfigRegistering())

        await coordinator.sync()

        #expect(api.getGeofencesCalls == [nil])
    }

    @Test func notModified_doesNotTouchCacheOrRegistrar() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .notModified }
        let cache = FakeGeofenceConfigCaching()
        cache.etag = "\"abc\""
        let registrar = FakeGeofenceConfigRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, cache: cache, registrar: registrar)

        await coordinator.sync()

        #expect(cache.etag == "\"abc\"")
        #expect(registrar.registeredCalls.isEmpty)
    }

    @Test func changed_cachesTheNewEtagAndRegistersAllGeofences() async {
        let api = FakeAPIClient()
        let config = GeofenceConfig(version: 5, geofences: [makeGeofence()])
        api.getGeofencesHandler = { _ in .ok(config, etag: "\"new\"") }
        let cache = FakeGeofenceConfigCaching()
        let registrar = FakeGeofenceConfigRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, cache: cache, registrar: registrar)

        await coordinator.sync()

        #expect(cache.etag == "\"new\"")
        #expect(registrar.registeredCalls == [[makeGeofence()]])
    }

    @Test func apiFailure_neverThrows_leavesCacheUntouched() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in throw APIError.transport("offline") }
        let cache = FakeGeofenceConfigCaching()
        cache.etag = "\"abc\""
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, cache: cache, registrar: FakeGeofenceConfigRegistering())

        await coordinator.sync()

        #expect(cache.etag == "\"abc\"")
    }
}

/// specs/001-api-contract.md §8.4, specs/009-device-runtime.md §5.4 — a thin delegate onto
/// `GeofenceConfigSyncCoordinator.sync()`. The push payload's own `etag` field is informational
/// only; the coordinator's cached ETag (via `If-None-Match`) is the actual source of truth, so the
/// handler ignores the payload entirely, exactly like Android's `GeofenceConfigChangedPushHandler`.
struct GeofenceConfigChangedPushHandlerTests {

    @Test func handle_delegatesToTheSyncCoordinator() async {
        let api = FakeAPIClient()
        let config = GeofenceConfig(version: 1, geofences: [])
        api.getGeofencesHandler = { _ in .ok(config, etag: "\"e1\"") }
        let cache = FakeGeofenceConfigCaching()
        let registrar = FakeGeofenceConfigRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, cache: cache, registrar: registrar)
        let handler = GeofenceConfigChangedPushHandler(syncCoordinator: coordinator)

        await handler.handle(["type": "GEOFENCE_CONFIG_CHANGED", "etag": "\"e1\""])

        #expect(api.getGeofencesCalls.count == 1)
        #expect(cache.etag == "\"e1\"")
        #expect(registrar.registeredCalls == [[]])
    }
}
