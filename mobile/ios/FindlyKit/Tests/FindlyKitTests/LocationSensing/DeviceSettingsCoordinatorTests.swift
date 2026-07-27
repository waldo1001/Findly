import Testing
@testable import FindlyKit

private final class FakeSyncScheduling: SyncScheduling {
    private(set) var rescheduleCalls: [Int] = []
    private(set) var cancelAllCallCount = 0
    func reschedule(syncIntervalMinutes: Int) { rescheduleCalls.append(syncIntervalMinutes) }
    func cancelAll() { cancelAllCallCount += 1 }
}

private final class FakeGeofenceRegistrarStub: GeofenceRegistrarStub {
    private(set) var unregisterAllCallCount = 0
    func unregisterAll() { unregisterAllCallCount += 1 }
}

/// specs/009-device-runtime.md §3.5/§4 — **the single settings-application entry point** every
/// arrival path (SETTINGS_CHANGED push [I12], the POST /locations piggyback, the paused-device
/// poll) calls. Mirrors Android's `DeviceSettingsCoordinator`.
struct DeviceSettingsCoordinatorTests {

    fileprivate func makeCoordinator(
        scheduler: FakeSyncScheduling = FakeSyncScheduling(),
        geofenceRegistrar: FakeGeofenceRegistrarStub = FakeGeofenceRegistrarStub(),
        stateStore: InMemoryDeviceSettingsStateStore = InMemoryDeviceSettingsStateStore(),
        onResume: @escaping () async -> Void = {}
    ) -> DeviceSettingsCoordinator {
        DeviceSettingsCoordinator(scheduler: scheduler, geofenceRegistrar: geofenceRegistrar, stateStore: stateStore, onResume: onResume)
    }

    @Test func firstApplication_rebuildsScheduleWithTheGivenInterval() async {
        let scheduler = FakeSyncScheduling()
        let coordinator = makeCoordinator(scheduler: scheduler)

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))

        #expect(scheduler.rescheduleCalls == [15])
    }

    @Test func trackingTurnedOff_cancelsScheduleAndUnregistersGeofences() async {
        let scheduler = FakeSyncScheduling()
        let geofenceRegistrar = FakeGeofenceRegistrarStub()
        let stateStore = InMemoryDeviceSettingsStateStore()
        let coordinator = makeCoordinator(scheduler: scheduler, geofenceRegistrar: geofenceRegistrar, stateStore: stateStore)
        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))

        #expect(scheduler.cancelAllCallCount == 1)
        #expect(geofenceRegistrar.unregisterAllCallCount == 1)
    }

    @Test func trackingTurnedOn_callsOnResume_andRebuildsSchedule() async {
        var resumeCallCount = 0
        let scheduler = FakeSyncScheduling()
        let stateStore = InMemoryDeviceSettingsStateStore()
        let coordinator = makeCoordinator(scheduler: scheduler, stateStore: stateStore, onResume: { resumeCallCount += 1 })
        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))

        #expect(resumeCallCount == 1)
        #expect(scheduler.rescheduleCalls == [15], "the second (resume) apply is the only one that should reschedule")
    }

    @Test func stateCachedBeforeActingOnIt() async {
        // specs/009 doc rationale: cache the new settings BEFORE touching the schedule/geofences,
        // so any capture racing this call already observes the new paused state.
        let stateStore = InMemoryDeviceSettingsStateStore()
        let coordinator = makeCoordinator(stateStore: stateStore)

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))

        #expect(stateStore.current()?.trackingEnabled == false)
    }

    @Test func applyingIdenticalSettingsTwice_isIdempotent_noExtraRebuild() async {
        let scheduler = FakeSyncScheduling()
        let coordinator = makeCoordinator(scheduler: scheduler)
        let snapshot = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true)

        await coordinator.applySettings(snapshot)
        await coordinator.applySettings(snapshot)

        #expect(scheduler.rescheduleCalls == [15], "the second identical apply must not rebuild again")
    }
}
