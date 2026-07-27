import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §3.5/§4 — pure decision function: "on any path, if
/// syncIntervalMinutes changed the schedule MUST be rebuilt immediately... if trackingEnabled
/// changed, apply §4."
struct SettingsChangeDecisionTests {

    @Test func firstEverApplication_previousNil_activeTarget_rebuildsAndCountsAsResume() {
        // previous == nil counts as "everything changed" (cold start / fresh install) - an active
        // target is treated the same as a resume (harmless: DeviceSettingsCoordinator's onResume
        // is a no-op the first time there's nothing to actually resume from).
        let next = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true)
        let actions = SettingsChangeDecision.decide(previous: nil, next: next)

        #expect(actions.rebuildSchedule)
        #expect(actions.pauseAction == .resume)
    }

    @Test func firstEverApplication_previousNil_pausedTarget_pauses() {
        let next = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)
        let actions = SettingsChangeDecision.decide(previous: nil, next: next)

        #expect(!actions.rebuildSchedule, "a paused target has nothing to schedule")
        #expect(actions.pauseAction == .pause)
    }

    @Test func intervalChanged_trackingUnchanged_rebuildsOnly() {
        let previous = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true)
        let next = DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true)
        let actions = SettingsChangeDecision.decide(previous: previous, next: next)

        #expect(actions.rebuildSchedule)
        #expect(actions.pauseAction == .none)
    }

    @Test func trackingTurnedOff_pausesAndDoesNotRebuild() {
        let previous = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true)
        let next = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)
        let actions = SettingsChangeDecision.decide(previous: previous, next: next)

        #expect(!actions.rebuildSchedule)
        #expect(actions.pauseAction == .pause)
    }

    @Test func trackingTurnedOn_resumesAndRebuildsEvenIfIntervalUnchanged() {
        let previous = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)
        let next = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true)
        let actions = SettingsChangeDecision.decide(previous: previous, next: next)

        #expect(actions.rebuildSchedule, "resume must restore the schedule even if the interval didn't change")
        #expect(actions.pauseAction == .resume)
    }

    @Test func nothingChanged_noActionAtAll() {
        let snapshot = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true)
        let actions = SettingsChangeDecision.decide(previous: snapshot, next: snapshot)

        #expect(!actions.rebuildSchedule)
        #expect(actions.pauseAction == .none)
    }

    @Test func pausedTarget_intervalChangeAlone_stillDoesNotRebuild() {
        let previous = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)
        let next = DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: false)
        let actions = SettingsChangeDecision.decide(previous: previous, next: next)

        #expect(!actions.rebuildSchedule, "a still-paused target has nothing to schedule regardless of interval")
        #expect(actions.pauseAction == .none)
    }
}
