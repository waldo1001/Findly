import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §8.3, specs/009-device-runtime.md §5.2 — `SETTINGS_CHANGED` always
/// carries the complete current values of both fields; applied idempotently via
/// `DeviceSettingsApplying` (never as a delta — that logic itself is `DeviceSettingsCoordinator`'s
/// job, already covered by `DeviceSettingsCoordinatorTests`). A malformed/partial payload is
/// dropped silently rather than applied partially (009 §5 intro).
struct SettingsChangedPushHandlerTests {

    private final class FakeDeviceSettingsApplying: DeviceSettingsApplying {
        private(set) var appliedSettings: [DeviceSettingsSnapshot] = []
        func applySettings(_ settings: DeviceSettingsSnapshot) async { appliedSettings.append(settings) }
    }

    @Test func fullPayload_appliesBothFields() async {
        let applying = FakeDeviceSettingsApplying()
        let handler = SettingsChangedPushHandler(settingsApplying: applying)

        await handler.handle(["type": "SETTINGS_CHANGED", "syncIntervalMinutes": "30", "trackingEnabled": "false"])

        #expect(applying.appliedSettings == [DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: false)])
    }

    @Test func missingSyncInterval_isDroppedSilently() async {
        let applying = FakeDeviceSettingsApplying()
        let handler = SettingsChangedPushHandler(settingsApplying: applying)

        await handler.handle(["trackingEnabled": "true"])

        #expect(applying.appliedSettings.isEmpty)
    }

    @Test func nonNumericSyncInterval_isDroppedSilently() async {
        let applying = FakeDeviceSettingsApplying()
        let handler = SettingsChangedPushHandler(settingsApplying: applying)

        await handler.handle(["syncIntervalMinutes": "soon", "trackingEnabled": "true"])

        #expect(applying.appliedSettings.isEmpty)
    }

    @Test func missingTrackingEnabled_isDroppedSilently() async {
        let applying = FakeDeviceSettingsApplying()
        let handler = SettingsChangedPushHandler(settingsApplying: applying)

        await handler.handle(["syncIntervalMinutes": "30"])

        #expect(applying.appliedSettings.isEmpty)
    }

    @Test func nonBooleanTrackingEnabled_isDroppedSilently() async {
        let applying = FakeDeviceSettingsApplying()
        let handler = SettingsChangedPushHandler(settingsApplying: applying)

        await handler.handle(["syncIntervalMinutes": "30", "trackingEnabled": "yes"])

        #expect(applying.appliedSettings.isEmpty)
    }

    @Test func appliedTwiceWithIdenticalValues_forwardsBothTimes() async {
        // Reorder/idempotency-safety of the OUTCOME is DeviceSettingsCoordinator's job; this
        // handler's only job is to parse-and-forward every well-formed payload it sees.
        let applying = FakeDeviceSettingsApplying()
        let handler = SettingsChangedPushHandler(settingsApplying: applying)

        await handler.handle(["syncIntervalMinutes": "30", "trackingEnabled": "true"])
        await handler.handle(["syncIntervalMinutes": "30", "trackingEnabled": "true"])

        #expect(applying.appliedSettings.count == 2)
    }
}
