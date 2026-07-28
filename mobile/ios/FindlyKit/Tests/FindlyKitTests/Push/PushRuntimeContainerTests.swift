import Foundation
import Testing
@testable import FindlyKit

private final class FakeDeviceSettingsApplying: DeviceSettingsApplying {
    private(set) var appliedSettings: [DeviceSettingsSnapshot] = []
    func applySettings(_ settings: DeviceSettingsSnapshot) async { appliedSettings.append(settings) }
}

private final class FakeGeofenceEventNotifying: GeofenceEventNotifying {
    private(set) var notifiedTitles: [String] = []
    func notify(title: String) { notifiedTitles.append(title) }
}

/// specs/009-device-runtime.md §5 — the composition root wiring all four push-type handlers into
/// one `PushMessageDispatcher`. Mirrors `LocationRuntimeContainerTests`: exercised end-to-end
/// against fakes for every real collaborator, confirming the wiring itself (not re-testing each
/// handler's own parsing logic, already covered by their dedicated test files).
struct PushRuntimeContainerTests {

    @Test func locateRequestPush_reachesLocationProviderAndApiClient() async {
        let location = FakeLocationProviding()
        location.nextFix = .success(LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:05:00Z", lat: 1, lon: 2, accuracyM: 5, batteryPct: 90, source: .locate))
        let api = FakeAPIClient()
        api.fulfillLocateRequestHandler = { _, _, _ in TestFeatures.envelope(FulfillLocateRequestResponse(status: "fulfilled")) }
        let container = PushRuntimeContainer(
            apiClient: api, locationProvider: location, deviceId: { "device-1" },
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventNotifier: FakeGeofenceEventNotifying()
        )

        // `now` isn't injectable through the container (the real app always uses the real clock),
        // so the fixture's `expiresAt` is computed relative to the actual wall clock at test time.
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))
        await container.dispatcher.dispatch(["type": "LOCATE_REQUEST", "requestId": "lr_1", "expiresAt": expiresAt])

        #expect(location.requestSingleFixCalls == [.locate])
        #expect(api.fulfillLocateRequestCalls.count == 1)
    }

    @Test func settingsChangedPush_reachesSettingsApplying() async {
        let settingsApplying = FakeDeviceSettingsApplying()
        let container = PushRuntimeContainer(
            apiClient: FakeAPIClient(), locationProvider: FakeLocationProviding(), deviceId: { "device-1" },
            settingsApplying: settingsApplying, geofenceEventNotifier: FakeGeofenceEventNotifying()
        )

        await container.dispatcher.dispatch(["type": "SETTINGS_CHANGED", "syncIntervalMinutes": "30", "trackingEnabled": "false"])

        #expect(settingsApplying.appliedSettings == [DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: false)])
    }

    @Test func geofenceEventPush_reachesTheNotifier() async {
        let notifier = FakeGeofenceEventNotifying()
        let container = PushRuntimeContainer(
            apiClient: FakeAPIClient(), locationProvider: FakeLocationProviding(), deviceId: { "device-1" },
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventNotifier: notifier
        )

        await container.dispatcher.dispatch(["type": "GEOFENCE_EVENT", "displayName": "Noor", "geofenceName": "Home", "transition": "enter"])

        #expect(notifier.notifiedTitles == ["Noor arrived at Home"])
    }

    @Test func geofenceConfigChangedPush_fetchesGeofences() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .notModified }
        let container = PushRuntimeContainer(
            apiClient: api, locationProvider: FakeLocationProviding(), deviceId: { "device-1" },
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventNotifier: FakeGeofenceEventNotifying()
        )

        await container.dispatcher.dispatch(["type": "GEOFENCE_CONFIG_CHANGED", "etag": "\"e1\""])

        #expect(api.getGeofencesCalls.count == 1)
    }
}
