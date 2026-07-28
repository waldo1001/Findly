import Foundation
import Testing
@testable import FindlyKit

/// **Post-review addition (security review, High finding).** `clear()` is the piece that makes
/// `LocationRuntimeContainer.wipeLocalState()` correctly leave `FixCaptureCoordinator`/
/// `GeofenceTransitionHandler`'s pause gates reading "paused" after a sign-out — see
/// `DeviceSettingsStateStoring.clear()`'s doc for why this must be an explicit
/// `trackingEnabled: false` write, not a bare "forget everything" the way
/// `GeofenceConfigStateStoring.clear()`/`FixQueue.clearAll()` are.
struct DeviceSettingsStateStoringTests {

    @Test func inMemory_clear_readsAsADefiniteNonNilPausedState_notMerelyUnknown() {
        let store = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true))

        store.clear()

        let current = store.current()
        #expect(current != nil, "clear() must NOT leave current() nil — nil reads as 'unknown, assume active' elsewhere in this codebase")
        #expect(current?.trackingEnabled == false)
    }

    @Test func inMemory_clear_preservesTheLastKnownSyncInterval() {
        let store = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true))

        store.clear()

        #expect(store.current()?.syncIntervalMinutes == 30)
    }

    @Test func inMemory_clear_withNothingCachedYet_stillProducesADefinitePausedState() {
        let store = InMemoryDeviceSettingsStateStore()

        store.clear()

        #expect(store.current()?.trackingEnabled == false)
    }

    @Test func userDefaults_clear_readsAsADefiniteNonNilPausedState() {
        let defaults = UserDefaults(suiteName: "DeviceSettingsStateStoringTests.\(UUID().uuidString)")!
        let store = UserDefaultsDeviceSettingsStateStore(defaults: defaults)
        store.update(DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))

        store.clear()

        let current = store.current()
        #expect(current != nil)
        #expect(current?.trackingEnabled == false)
        #expect(current?.syncIntervalMinutes == 15)
    }

    @Test func userDefaults_clear_persistsAcrossAFreshInstance() {
        let defaults = UserDefaults(suiteName: "DeviceSettingsStateStoringTests.\(UUID().uuidString)")!
        UserDefaultsDeviceSettingsStateStore(defaults: defaults).clear()

        let reopened = UserDefaultsDeviceSettingsStateStore(defaults: defaults)
        #expect(reopened.current()?.trackingEnabled == false)
    }
}
