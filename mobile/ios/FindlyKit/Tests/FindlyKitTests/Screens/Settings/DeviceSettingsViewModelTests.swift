import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §4.2–4.3) — device list + settings, parent-vs-owner permission
/// gating.
@MainActor
struct DeviceSettingsViewModelTests {

    func makeDevice(_ id: String = "d1", trackingEnabled: Bool = true, syncIntervalMinutes: Int = 15) -> DeviceListItem {
        DeviceListItem(
            deviceId: id, ownerUserId: "u1", platform: "ios", deviceName: "Eric's phone", model: "iPhone 15",
            appVersion: "1.0.0", syncIntervalMinutes: syncIntervalMinutes, trackingEnabled: trackingEnabled,
            pushInvalid: false, ownerDisplayName: "Eric", lastSeenAt: "2026-07-19T09:00:00Z"
        )
    }

    @Test func load_success_populatesState() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)

        await viewModel.load()

        #expect(viewModel.state == .loaded([makeDevice()]))
    }

    @Test func load_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { throw APIError.transport("offline") }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func setTrackingEnabled_asParent_updatesTheMatchingDeviceInPlace() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice(trackingEnabled: true)])) }
        api.updateDeviceHandler = { deviceId, request in
            #expect(deviceId == "d1")
            #expect(request.trackingEnabled == false)
            return TestFeatures.envelope(DeviceResponse(
                deviceId: "d1", ownerUserId: "u1", platform: "ios", deviceName: "Eric's phone", model: "iPhone 15",
                appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: false, pushInvalid: false
            ))
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()

        await viewModel.setTrackingEnabled(deviceId: "d1", false)

        #expect(viewModel.state == .loaded([makeDevice(trackingEnabled: false)]))
        #expect(viewModel.lastActionError == nil)
        #expect(api.updateDeviceCalls.count == 1)
    }

    @Test func setSyncInterval_asNonParent_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: false)
        await viewModel.load()

        await viewModel.setSyncInterval(deviceId: "d1", minutes: 30)

        #expect(api.updateDeviceCalls.isEmpty)
        #expect(viewModel.lastActionError != nil)
        #expect(viewModel.state == .loaded([makeDevice()]), "a rejected update must not mutate the loaded list")
    }

    @Test func update_serverError_setsLastActionError_withoutDiscardingTheLoadedList() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        api.updateDeviceHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .limitExceeded, message: "floor", details: nil, requestId: "r1"), httpStatus: 402)
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()

        await viewModel.setSyncInterval(deviceId: "d1", minutes: 5)

        #expect(viewModel.lastActionError != nil)
        #expect(viewModel.state == .loaded([makeDevice()]))
    }

    // MARK: - rename (review-gate finding #4 — previously dead code, now wired into DeviceSettingsScreen)

    @Test func rename_asParent_updatesTheMatchingDeviceInPlace() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        api.updateDeviceHandler = { deviceId, request in
            #expect(deviceId == "d1")
            #expect(request.deviceName == "Noor's tablet")
            return TestFeatures.envelope(DeviceResponse(
                deviceId: "d1", ownerUserId: "u1", platform: "ios", deviceName: "Noor's tablet", model: "iPhone 15",
                appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: true, pushInvalid: false
            ))
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()

        await viewModel.rename(deviceId: "d1", name: "Noor's tablet")

        guard case .loaded(let devices) = viewModel.state else {
            Issue.record("expected .loaded state")
            return
        }
        #expect(devices.first?.deviceName == "Noor's tablet")
        #expect(viewModel.lastActionError == nil)
        #expect(api.updateDeviceCalls.count == 1)
    }

    @Test func rename_asNonParent_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: false)
        await viewModel.load()

        await viewModel.rename(deviceId: "d1", name: "New name")

        #expect(api.updateDeviceCalls.isEmpty)
        #expect(viewModel.lastActionError != nil)
        #expect(viewModel.state == .loaded([makeDevice()]))
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §2.1 (I34) — the profile-dead-end routing rule.
    // `GET /devices` works without a family (001 §1.5.4/§4), so only `PROFILE_NOT_FOUND` is
    // actually reachable here — the classifier is still generic/shared across all seven screens.

    @Test func load_profileNotFound_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.profileLess))
    }
}
