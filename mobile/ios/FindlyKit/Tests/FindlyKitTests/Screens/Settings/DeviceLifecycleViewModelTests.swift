import Testing
@testable import FindlyKit

/// specs/011 §1.1, §4.4; specs/010 §4.2, §9 — remove + nudge-toggle behaviour of the Devices view model.
@MainActor
struct DeviceLifecycleViewModelTests {
    private func device(_ id: String, owner: String = "u2", nudge: Bool = true) -> DeviceListItem {
        DeviceListItem(
            deviceId: id, ownerUserId: owner, platform: "ios", deviceName: "Phone \(id)", model: "iPhone",
            appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: true, pushInvalid: false,
            ownerDisplayName: "Noor", lastSeenAt: "2026-07-19T09:00:00Z", staleNudgeEnabled: nudge
        )
    }

    private func apiError(_ code: APIErrorCode, status: Int) -> APIError {
        .server(APIErrorBody(code: code, message: "m", details: nil, requestId: "r"), httpStatus: status)
    }

    private func loadedViewModel(
        _ api: FakeAPIClient, isParent: Bool, devices: [DeviceListItem]
    ) async -> DeviceSettingsViewModel {
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: devices)) }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: isParent, currentUserId: "u1", thisDeviceId: "d-this")
        await viewModel.load()
        return viewModel
    }

    // MARK: remove

    @Test func remove_204_dropsTheCard_andCallsDeleteOnce() async {
        let api = FakeAPIClient()
        api.deleteDeviceHandler = { _ in }
        let viewModel = await loadedViewModel(api, isParent: true, devices: [device("d1"), device("d2")])

        await viewModel.remove(deviceId: "d1")

        #expect(api.deleteDeviceCalls == ["d1"])
        #expect(viewModel.state == .loaded([device("d2")]))
        #expect(viewModel.error(forDeviceId: "d1") == nil)
    }

    @Test func remove_deviceNotFound_isSuccess_dropsCard_andRefreshesTheList() async {
        let api = FakeAPIClient()
        api.deleteDeviceHandler = { _ in throw self.apiError(.deviceNotFound, status: 404) }
        let viewModel = await loadedViewModel(api, isParent: true, devices: [device("d1"), device("d2")])
        let loadsBefore = api.listDevicesCallCount
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.device("d2")])) }

        await viewModel.remove(deviceId: "d1")

        #expect(api.listDevicesCallCount == loadsBefore + 1)
        #expect(viewModel.state == .loaded([device("d2")]))
        #expect(viewModel.error(forDeviceId: "d1") == nil)
    }

    @Test func remove_authForbidden_rendersOnTheCard_andKeepsIt() async {
        let api = FakeAPIClient()
        api.deleteDeviceHandler = { _ in throw self.apiError(.authForbidden, status: 403) }
        let viewModel = await loadedViewModel(api, isParent: true, devices: [device("d1")])

        await viewModel.remove(deviceId: "d1")

        #expect(viewModel.error(forDeviceId: "d1") == "Only a parent can remove another member's device.")
        #expect(viewModel.state == .loaded([device("d1")]))
    }

    @Test func remove_otherFailure_rendersOnTheCard_andKeepsIt() async {
        let api = FakeAPIClient()
        api.deleteDeviceHandler = { _ in throw APIError.transport("offline") }
        let viewModel = await loadedViewModel(api, isParent: true, devices: [device("d1")])

        await viewModel.remove(deviceId: "d1")

        #expect(viewModel.error(forDeviceId: "d1") != nil)
        #expect(viewModel.state == .loaded([device("d1")]))
    }

    @Test func remove_onThisDevice_isRefused_withoutANetworkCall() async {
        let api = FakeAPIClient()
        let viewModel = await loadedViewModel(api, isParent: true, devices: [device("d-this", owner: "u1")])

        await viewModel.remove(deviceId: "d-this")

        #expect(api.deleteDeviceCalls.isEmpty)
        #expect(viewModel.state == .loaded([device("d-this", owner: "u1")]))
    }

    @Test func canRemove_followsTheVisibilityMatrix() async {
        let api = FakeAPIClient()
        let parent = await loadedViewModel(api, isParent: true, devices: [])
        #expect(parent.canRemove(device("d2", owner: "u2")))
        #expect(!parent.canRemove(device("d-this", owner: "u1")))
        let member = await loadedViewModel(api, isParent: false, devices: [])
        #expect(member.canRemove(device("d3", owner: "u1")))
        #expect(!member.canRemove(device("d2", owner: "u2")))
    }

    // MARK: nudge toggle

    @Test func showsNudgeToggle_onlyOnOwnedDevices() async {
        let api = FakeAPIClient()
        let viewModel = await loadedViewModel(api, isParent: true, devices: [])
        #expect(viewModel.showsNudgeToggle(device("d1", owner: "u1")))
        #expect(!viewModel.showsNudgeToggle(device("d2", owner: "u2")))
    }

    @Test func setStaleNudgeEnabled_commitsOnePatch_withOnlyThatField_forAnOwnerNonParent() async {
        let api = FakeAPIClient()
        api.updateDeviceHandler = { id, _ in
            TestFeatures.envelope(DeviceResponse(
                deviceId: id, ownerUserId: "u1", platform: "ios", deviceName: "Phone d1", model: "iPhone",
                appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: true, pushInvalid: false,
                staleNudgeEnabled: false
            ))
        }
        let viewModel = await loadedViewModel(api, isParent: false, devices: [device("d1", owner: "u1")])

        await viewModel.setStaleNudgeEnabled(deviceId: "d1", false)

        #expect(api.updateDeviceCalls.count == 1)
        #expect(api.updateDeviceCalls[0].deviceId == "d1")
        #expect(api.updateDeviceCalls[0].request == UpdateDeviceRequest(staleNudgeEnabled: false))
        #expect(viewModel.state == .loaded([device("d1", owner: "u1", nudge: false)]))
    }

    @Test func setStaleNudgeEnabled_onSomeoneElsesDevice_isRefused_withoutANetworkCall() async {
        let api = FakeAPIClient()
        let viewModel = await loadedViewModel(api, isParent: true, devices: [device("d2", owner: "u2")])

        await viewModel.setStaleNudgeEnabled(deviceId: "d2", false)

        #expect(api.updateDeviceCalls.isEmpty)
    }

    @Test func setStaleNudgeEnabled_failure_rendersOnTheCard() async {
        let api = FakeAPIClient()
        api.updateDeviceHandler = { _, _ in throw APIError.transport("offline") }
        let viewModel = await loadedViewModel(api, isParent: false, devices: [device("d1", owner: "u1")])

        await viewModel.setStaleNudgeEnabled(deviceId: "d1", false)

        #expect(viewModel.error(forDeviceId: "d1") != nil)
    }
}
