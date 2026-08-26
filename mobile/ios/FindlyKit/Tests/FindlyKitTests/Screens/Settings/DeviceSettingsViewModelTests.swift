import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §4.2–4.3) — device list + settings, parent-vs-owner permission
/// gating. specs/010-app-shell-and-screen-ux.md §4.2 (I36): errors from a card's own mutation
/// render on that card, not pooled into one shared `lastActionError` — `error(forDeviceId:)`
/// replaces it, keyed per device so one device's failure can never bleed onto another's card.
/// `minSyncIntervalMinutes` mirrors `features.limits.minSyncIntervalMinutes` (001 §9) for the
/// sync-interval `FindlyDropdownField`'s floor — CLAUDE.md: limits always come from `features`,
/// never a call-site literal.
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
        #expect(viewModel.error(forDeviceId: "d1") == nil)
        #expect(api.updateDeviceCalls.count == 1)
    }

    @Test func setSyncInterval_asNonParent_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: false)
        await viewModel.load()

        await viewModel.setSyncInterval(deviceId: "d1", minutes: 30)

        #expect(api.updateDeviceCalls.isEmpty)
        #expect(viewModel.error(forDeviceId: "d1") != nil)
        #expect(viewModel.state == .loaded([makeDevice()]), "a rejected update must not mutate the loaded list")
    }

    @Test func update_serverError_setsThatDevicesCardError_withoutDiscardingTheLoadedList() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        api.updateDeviceHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .limitExceeded, message: "floor", details: nil, requestId: "r1"), httpStatus: 402)
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()

        await viewModel.setSyncInterval(deviceId: "d1", minutes: 5)

        #expect(viewModel.error(forDeviceId: "d1") != nil)
        #expect(viewModel.state == .loaded([makeDevice()]))
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §4.2 (I36) — per-card error isolation. The
    // shared top-of-list `lastActionError` this replaces could not express this: a second
    // device's card must never show a first device's failure, and a later success on the first
    // device must clear only that device's own error.

    @Test func aFailureOnOneDevice_neverSurfacesOnAnotherDevicesCard() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice("d1"), self.makeDevice("d2")]))
        }
        api.updateDeviceHandler = { deviceId, _ in
            throw APIError.server(APIErrorBody(code: .limitExceeded, message: "floor", details: nil, requestId: "r1"), httpStatus: 402)
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()

        await viewModel.setSyncInterval(deviceId: "d1", minutes: 5)

        #expect(viewModel.error(forDeviceId: "d1") != nil)
        #expect(viewModel.error(forDeviceId: "d2") == nil, "device d2 never mutated — it must not inherit d1's error")
    }

    @Test func aSuccessOnOneDevice_clearsOnlyThatDevicesCardError_leavingAnotherDevicesErrorIntact() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice("d1"), self.makeDevice("d2")]))
        }
        var callCount = 0
        api.updateDeviceHandler = { deviceId, request in
            callCount += 1
            if deviceId == "d1" {
                throw APIError.server(APIErrorBody(code: .limitExceeded, message: "floor", details: nil, requestId: "r1"), httpStatus: 402)
            }
            return TestFeatures.envelope(DeviceResponse(
                deviceId: "d2", ownerUserId: "u1", platform: "ios", deviceName: "Eric's phone", model: "iPhone 15",
                appVersion: "1.0.0", syncIntervalMinutes: 30, trackingEnabled: true, pushInvalid: false
            ))
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()
        await viewModel.setSyncInterval(deviceId: "d1", minutes: 5)
        #expect(viewModel.error(forDeviceId: "d1") != nil)

        await viewModel.setSyncInterval(deviceId: "d2", minutes: 30)

        #expect(viewModel.error(forDeviceId: "d2") == nil)
        #expect(viewModel.error(forDeviceId: "d1") != nil, "d1's own error is untouched by d2's unrelated success")
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
        #expect(viewModel.error(forDeviceId: "d1") == nil)
        #expect(api.updateDeviceCalls.count == 1)
    }

    @Test func rename_asNonParent_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()])) }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: false)
        await viewModel.load()

        await viewModel.rename(deviceId: "d1", name: "New name")

        #expect(api.updateDeviceCalls.isEmpty)
        #expect(viewModel.error(forDeviceId: "d1") != nil)
        #expect(viewModel.state == .loaded([makeDevice()]))
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §4.2/§9 (I36) — the sync-interval floor comes
    // from `features.limits.minSyncIntervalMinutes`, never a hardcoded value.

    @Test func load_capturesTheSyncIntervalFloor_fromFeatures_notALiteral() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()]), minSyncIntervalMinutes: 30)
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)

        await viewModel.load()

        #expect(viewModel.minSyncIntervalMinutes == 30)
    }

    @Test func update_refreshesTheSyncIntervalFloor_fromTheMutationResponsesFeatures() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [self.makeDevice()]), minSyncIntervalMinutes: 5)
        }
        api.updateDeviceHandler = { deviceId, _ in
            TestFeatures.envelope(
                DeviceResponse(
                    deviceId: "d1", ownerUserId: "u1", platform: "ios", deviceName: "Eric's phone", model: "iPhone 15",
                    appVersion: "1.0.0", syncIntervalMinutes: 60, trackingEnabled: true, pushInvalid: false
                ),
                minSyncIntervalMinutes: 60
            )
        }
        let viewModel = DeviceSettingsViewModel(apiClient: api, isParent: true)
        await viewModel.load()
        #expect(viewModel.minSyncIntervalMinutes == 5)

        await viewModel.setSyncInterval(deviceId: "d1", minutes: 60)

        #expect(viewModel.minSyncIntervalMinutes == 60)
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
