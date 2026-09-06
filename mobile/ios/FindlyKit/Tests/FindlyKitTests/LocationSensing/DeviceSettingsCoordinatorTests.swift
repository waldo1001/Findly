import Testing
@testable import FindlyKit

private final class FakeSyncScheduling: SyncScheduling {
    private(set) var rescheduleCalls: [Int] = []
    func reschedule(syncIntervalMinutes: Int) { rescheduleCalls.append(syncIntervalMinutes) }
}

private final class FakeGeofenceRegistrarStub: GeofenceRegistrarStub {
    private(set) var unregisterAllCallCount = 0
    func unregisterAll() { unregisterAllCallCount += 1 }
}

/// specs/009-device-runtime.md §3.5/§4 — **the single settings-application entry point** every
/// arrival path (SETTINGS_CHANGED push [I12], the POST /locations piggyback, the paused-device
/// poll) calls. Mirrors Android's `DeviceSettingsCoordinator`, with one deliberate iOS-specific
/// divergence: pausing does NOT cancel the BG task (see `SyncScheduling`'s doc for why — the BG
/// task is the only thing keeping the pull-based resume alive while paused, specs/009 §4).
struct DeviceSettingsCoordinatorTests {

    fileprivate func makeCoordinator(
        scheduler: FakeSyncScheduling = FakeSyncScheduling(),
        geofenceRegistrar: FakeGeofenceRegistrarStub = FakeGeofenceRegistrarStub(),
        stateStore: InMemoryDeviceSettingsStateStore = InMemoryDeviceSettingsStateStore(),
        onPause: @escaping () -> Void = {},
        onResume: @escaping () async -> Void = {},
        reconcilePresence: @escaping () async -> Void = {}
    ) -> DeviceSettingsCoordinator {
        DeviceSettingsCoordinator(scheduler: scheduler, geofenceRegistrar: geofenceRegistrar, stateStore: stateStore, onPause: onPause, onResume: onResume, reconcilePresence: reconcilePresence)
    }

    @Test func firstApplication_rebuildsScheduleWithTheGivenInterval() async {
        let scheduler = FakeSyncScheduling()
        let coordinator = makeCoordinator(scheduler: scheduler)

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))

        #expect(scheduler.rescheduleCalls == [15])
    }

    @Test func trackingTurnedOff_unregistersGeofencesAndStopsCapturing_butDoesNotTouchTheSchedule() async {
        let scheduler = FakeSyncScheduling()
        let geofenceRegistrar = FakeGeofenceRegistrarStub()
        let stateStore = InMemoryDeviceSettingsStateStore()
        var pauseCallCount = 0
        let coordinator = makeCoordinator(scheduler: scheduler, geofenceRegistrar: geofenceRegistrar, stateStore: stateStore, onPause: { pauseCallCount += 1 })
        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))

        #expect(pauseCallCount == 1, "specs/009 §4 'and stop capturing' - onPause is what stops significant-location-change monitoring")
        #expect(geofenceRegistrar.unregisterAllCallCount == 1)
        // Blocking-finding regression guard: pausing MUST NOT touch the BG task schedule at all -
        // it's the only thing that keeps running while paused (specs/009 §4's pull-based resume).
        #expect(scheduler.rescheduleCalls == [15], "only the first (active) apply should have rescheduled; pausing must not reschedule OR cancel")
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

    // MARK: - I52: presence reconciliation (specs/009 §1.3/§3.5) — "on ANY path, if
    // syncIntervalMinutes changed the schedule MUST be rebuilt immediately... start or stop the
    // presence service/session per §1.3 when the interval crosses the 30/60 boundary." This is the
    // single call every settings-arrival path (SETTINGS_CHANGED push, the piggyback, the
    // paused-device poll) funnels through, so `reconcilePresence` must fire unconditionally - not
    // only on a pause/resume transition, and not skipped on an idempotent re-apply.

    @Test func applySettings_reconcilesPresence_onEveryApplication_regardlessOfWhatChanged() async {
        var reconcileCallCount = 0
        let coordinator = makeCoordinator(reconcilePresence: { reconcileCallCount += 1 })

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))
        #expect(reconcileCallCount == 1, "first application")

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))
        #expect(reconcileCallCount == 2, "an idempotent re-apply must still reconcile presence")

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: true))
        #expect(reconcileCallCount == 3, "an interval-only change crossing the 30/60 boundary must reconcile presence")

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: false))
        #expect(reconcileCallCount == 4, "pause must reconcile presence (which will decide to stop it)")

        await coordinator.applySettings(DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: true))
        #expect(reconcileCallCount == 5, "resume must reconcile presence (which will decide whether to start it)")
    }
}
