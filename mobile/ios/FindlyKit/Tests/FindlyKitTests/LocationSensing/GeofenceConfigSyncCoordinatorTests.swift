import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §6.2 — the fetch/cache/full-replace-register sequence, and the
/// ETag-mismatch gate. Mirrors Android's `GeofenceConfigSyncCoordinatorTest`.
struct GeofenceConfigSyncCoordinatorTests {

    func makeGeofence(_ id: String = "gf_home") -> Geofence {
        Geofence(geofenceId: id, name: "Home", lat: 51.0, lon: 3.7, radiusM: 150, icon: "home", notifyOnEnter: true, notifyOnExit: true)
    }

    @Test func sync_freshConfig_updatesCacheAndRegistersAll() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { ifNoneMatch in
            #expect(ifNoneMatch == nil, "nothing cached yet")
            return .ok(GeofenceConfig(version: 4, geofences: [self.makeGeofence()]), etag: "\"0x1\"", features: TestFeatures.free)
        }
        let store = InMemoryGeofenceConfigStateStore()
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.sync()

        #expect(store.current() == CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()]))
        #expect(registrar.registerAllCalls.count == 1)
        #expect(registrar.registerAllCalls.first?.geofences == [makeGeofence()])
        #expect(registrar.registerAllCalls.first?.etag == "\"0x1\"")
    }

    @Test func sync_sendsTheCachedEtagAsIfNoneMatch() async {
        let api = FakeAPIClient()
        let store = InMemoryGeofenceConfigStateStore(initial: CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()]))
        api.getGeofencesHandler = { ifNoneMatch in
            #expect(ifNoneMatch == "\"0x1\"")
            return .notModified
        }
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.sync()

        #expect(registrar.unregisterAllCallCount == 0, "registerAll itself owns the unregister half")
    }

    @Test func sync_notModified_stillReRegistersFromCache() async {
        // Resume/cold-start need the OS-level registrations rebuilt even when the config itself
        // is unchanged (specs/009 §6.2) - the OS lost the registration, not the config.
        let api = FakeAPIClient()
        let cached = CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()])
        let store = InMemoryGeofenceConfigStateStore(initial: cached)
        api.getGeofencesHandler = { _ in .notModified }
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.sync()

        #expect(registrar.registerAllCalls.count == 1)
        #expect(registrar.registerAllCalls.first?.geofences == [makeGeofence()])
        #expect(registrar.registerAllCalls.first?.etag == "\"0x1\"")
    }

    @Test func sync_notModified_nothingCachedYet_isASilentNoOp() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .notModified }
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: InMemoryGeofenceConfigStateStore(), registrar: registrar)

        await coordinator.sync()

        #expect(registrar.registerAllCalls.isEmpty)
    }

    @Test func sync_apiFailure_reRegistersFromWhateverIsCached() async {
        let api = FakeAPIClient()
        let cached = CachedGeofenceConfig(etag: "\"0x1\"", geofences: [makeGeofence()])
        let store = InMemoryGeofenceConfigStateStore(initial: cached)
        api.getGeofencesHandler = { _ in throw APIError.transport("offline") }
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.sync()

        #expect(registrar.registerAllCalls.count == 1)
        #expect(registrar.registerAllCalls.first?.geofences == [makeGeofence()])
    }

    @Test func sync_apiFailure_nothingCachedYet_isASilentNoOp() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in throw APIError.transport("offline") }
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: InMemoryGeofenceConfigStateStore(), registrar: registrar)

        await coordinator.sync()

        #expect(registrar.registerAllCalls.isEmpty)
    }

    // MARK: - specs/000 §O9 - the 20-region platform ceiling

    @Test func sync_capsAtThePlatformCeiling_evenWhenTheServerLimitIsHigher() async {
        let api = FakeAPIClient()
        let manyGeofences = (0..<25).map { makeGeofence("gf_\($0)") }
        let generousFeatures = Features(
            subscriptionStatus: "paid",
            limits: PlanLimits(maxDevices: 10, maxGeofences: 25, historyDays: 90, minSyncIntervalMinutes: 5, locateRequestsPerDay: 100),
            flags: PlanFlags(pushToLocate: true, geofencing: true, historyReplay: true)
        )
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: manyGeofences), etag: "\"0x1\"", features: generousFeatures) }
        let store = InMemoryGeofenceConfigStateStore()
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.sync()

        #expect(store.current()?.geofences.count == 20, "specs/000 §O9: CLLocationManager's own 20-region cap, independent of the server limit")
        #expect(registrar.registerAllCalls.first?.geofences.count == 20)
    }

    @Test func sync_capsAtTheServerLimitWhenItsLowerThanThePlatformCeiling() async {
        let api = FakeAPIClient()
        let someGeofences = (0..<10).map { makeGeofence("gf_\($0)") }
        let narrowFeatures = Features(
            subscriptionStatus: "free",
            limits: PlanLimits(maxDevices: 10, maxGeofences: 3, historyDays: 90, minSyncIntervalMinutes: 5, locateRequestsPerDay: 100),
            flags: PlanFlags(pushToLocate: true, geofencing: true, historyReplay: true)
        )
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: someGeofences), etag: "\"0x1\"", features: narrowFeatures) }
        let store = InMemoryGeofenceConfigStateStore()
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.sync()

        #expect(store.current()?.geofences.count == 3)
    }

    // MARK: - syncIfEtagChanged (the §6.2/§6.3 piggyback trigger)

    @Test func syncIfEtagChanged_matchesCachedEtag_doesNotFetch() async {
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in getGeofencesCallCount += 1; return .notModified }
        let store = InMemoryGeofenceConfigStateStore(initial: CachedGeofenceConfig(etag: "\"0x1\"", geofences: []))
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: FakeGeofenceRegistering())

        await coordinator.syncIfEtagChanged("\"0x1\"")

        #expect(getGeofencesCallCount == 0)
    }

    @Test func syncIfEtagChanged_differsFromCachedEtag_triggersAFullSync() async {
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in
            getGeofencesCallCount += 1
            return .ok(GeofenceConfig(version: 2, geofences: [self.makeGeofence()]), etag: "\"0x2\"", features: TestFeatures.free)
        }
        let store = InMemoryGeofenceConfigStateStore(initial: CachedGeofenceConfig(etag: "\"0x1\"", geofences: []))
        let registrar = FakeGeofenceRegistering()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: registrar)

        await coordinator.syncIfEtagChanged("\"0x2\"")

        #expect(getGeofencesCallCount == 1)
        #expect(store.current()?.etag == "\"0x2\"")
        #expect(registrar.registerAllCalls.count == 1)
    }

    @Test func syncIfEtagChanged_nothingCachedYet_anyObservedEtagTriggersTheFirstSync() async {
        // specs/009 §6.2's "first config sync after sign-in" naturally falls out of this: a
        // freshly-signed-in device's cache starts nil, so the very first piggyback's etag (even
        // the family-less "0" sentinel, 001 §5.1) always differs from nil and triggers a sync.
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in
            getGeofencesCallCount += 1
            return .ok(GeofenceConfig(version: 0, geofences: []), etag: "0", features: TestFeatures.free)
        }
        let store = InMemoryGeofenceConfigStateStore()
        let coordinator = GeofenceConfigSyncCoordinator(apiClient: api, configStore: store, registrar: FakeGeofenceRegistering())

        await coordinator.syncIfEtagChanged("0")

        #expect(getGeofencesCallCount == 1)
        #expect(store.current()?.etag == "0")
    }

    @Test func noOpGeofenceConfigSyncing_isASafeDefault() async {
        // The `LocationSyncRunner`/`LocationRuntimeContainer` default - proves it genuinely does
        // nothing observable, no crash, no side effect.
        let noOp = NoOpGeofenceConfigSyncing()
        await noOp.syncIfEtagChanged("anything")
    }
}
