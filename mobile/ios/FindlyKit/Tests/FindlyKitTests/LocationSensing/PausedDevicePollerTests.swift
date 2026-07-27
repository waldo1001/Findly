import Testing
@testable import FindlyKit

private final class FakeDeviceSettingsApplying: DeviceSettingsApplying {
    private(set) var appliedSettings: [DeviceSettingsSnapshot] = []
    func applySettings(_ settings: DeviceSettingsSnapshot) async { appliedSettings.append(settings) }
}

fileprivate func makeDeviceListItem(deviceId: String, syncIntervalMinutes: Int, trackingEnabled: Bool) -> DeviceListItem {
    DeviceListItem(
        deviceId: deviceId, ownerUserId: "user-1", platform: "ios", deviceName: "iPhone", model: "iPhone15,2",
        appVersion: "1.0.0", syncIntervalMinutes: syncIntervalMinutes, trackingEnabled: trackingEnabled,
        pushInvalid: false, ownerDisplayName: "Alex", lastSeenAt: "2026-07-19T09:00:00Z"
    )
}

/// specs/009-device-runtime.md §4 / §3.5's third settings-arrival path — "while paused the client
/// MUST re-check its settings via `GET /devices` on every app foreground and at least every 6
/// hours." Mirrors Android's `SettingsPoller`.
struct PausedDevicePollerTests {

    @Test func noDeviceId_failsWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let settingsApplying = FakeDeviceSettingsApplying()
        let poller = PausedDevicePoller(apiClient: api, deviceId: { nil }, settingsApplying: settingsApplying)

        let outcome = await poller.poll()

        #expect(outcome == .failed)
        #expect(api.listDevicesCallCount == 0)
    }

    @Test func ownDevicePresent_appliesItsSettings() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                makeDeviceListItem(deviceId: "other-device", syncIntervalMinutes: 15, trackingEnabled: true),
                makeDeviceListItem(deviceId: "device-1", syncIntervalMinutes: 60, trackingEnabled: true),
            ]))
        }
        let settingsApplying = FakeDeviceSettingsApplying()
        let poller = PausedDevicePoller(apiClient: api, deviceId: { "device-1" }, settingsApplying: settingsApplying)

        let outcome = await poller.poll()

        #expect(outcome == .applied)
        #expect(settingsApplying.appliedSettings == [DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: true)])
    }

    @Test func ownDeviceAbsentFromTheRoster_returnsDeviceNotFound() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [])) }
        let settingsApplying = FakeDeviceSettingsApplying()
        let poller = PausedDevicePoller(apiClient: api, deviceId: { "device-1" }, settingsApplying: settingsApplying)

        let outcome = await poller.poll()

        #expect(outcome == .deviceNotFound)
        #expect(settingsApplying.appliedSettings.isEmpty)
    }

    @Test func apiFailure_returnsFailed_neverThrows() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { throw APIError.transport("offline") }
        let settingsApplying = FakeDeviceSettingsApplying()
        let poller = PausedDevicePoller(apiClient: api, deviceId: { "device-1" }, settingsApplying: settingsApplying)

        let outcome = await poller.poll()

        #expect(outcome == .failed)
    }

    @Test func harmlessWhenNotActuallyPaused_appliesWhateverServerSaysIdempotently() async {
        // "Harmless to call when not paused" (per class doc) - applySettings itself is a no-op
        // unless something changed; the poller doesn't need to know current pause state.
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [makeDeviceListItem(deviceId: "device-1", syncIntervalMinutes: 15, trackingEnabled: true)]))
        }
        let settingsApplying = FakeDeviceSettingsApplying()
        let poller = PausedDevicePoller(apiClient: api, deviceId: { "device-1" }, settingsApplying: settingsApplying)

        let outcome = await poller.poll()

        #expect(outcome == .applied)
    }
}
