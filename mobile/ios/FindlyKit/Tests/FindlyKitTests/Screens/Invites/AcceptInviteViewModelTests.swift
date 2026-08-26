import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §3.4; security checklist §5 — deep-link inputs validated
/// before use).
@MainActor
struct AcceptInviteViewModelTests {

    @Test func accept_malformedCode_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "not-a-code", displayName: "Noor")

        #expect(api.acceptInviteCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func accept_emptyDisplayName_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "7F3K9QRZ", displayName: "   ")

        #expect(api.acceptInviteCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func accept_deepLinkCode_isNormalizedBeforeSending() async {
        let api = FakeAPIClient()
        api.acceptInviteHandler = { code, displayName in
            #expect(code == "7F3K9QRZ")
            #expect(displayName == "Noor")
            return TestFeatures.envelope(AcceptInviteResponse(familyId: "fam_x", familyName: "Wauters", role: "member"))
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "findly://invite/7f3k9qrz", displayName: "Noor")

        #expect(viewModel.state == .joined(familyId: "fam_x", familyName: "Wauters", role: "member"))
    }

    @Test func accept_serverError_setsErrorState() async {
        let api = FakeAPIClient()
        api.acceptInviteHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .inviteExpired, message: "expired", details: nil, requestId: "r1"), httpStatus: 410)
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "7F3K9QRZ", displayName: "Noor")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §5.2, specs/001-api-contract.md §4.2 —
    // prefilling the display-name field from the caller's OWN existing profile displayName (a
    // family-less caller's own devices' ownerDisplayName), when there's no Onboarding-typed name
    // to prefill from instead.

    @Test func resolveExistingDisplayName_usesOwnerDisplayNameFromTheFirstDevice() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "d1", ownerUserId: "u1", platform: "ios", deviceName: "Noor's iPhone",
                    model: "iPhone15", appVersion: "1.0", syncIntervalMinutes: 15, trackingEnabled: true,
                    pushInvalid: false, ownerDisplayName: "Noor", lastSeenAt: "2026-07-19T09:05:14Z"
                )
            ]))
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.resolveExistingDisplayName()

        #expect(viewModel.resolvedDisplayName == "Noor")
    }

    @Test func resolveExistingDisplayName_noDevicesYet_staysNil() async {
        let api = FakeAPIClient()
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [])) }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.resolveExistingDisplayName()

        #expect(viewModel.resolvedDisplayName == nil)
    }

    @Test func resolveExistingDisplayName_apiFailure_staysNilWithoutThrowing() async {
        // A profile-less caller's GET /devices 404s PROFILE_NOT_FOUND — this is a convenience
        // prefill, never on the join's critical path, so any failure degrades to "no prefill",
        // not an error state.
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.resolveExistingDisplayName()

        #expect(viewModel.resolvedDisplayName == nil)
        guard case .idle = viewModel.state else {
            Issue.record("a resolveExistingDisplayName failure must never touch join state, got \(viewModel.state)")
            return
        }
    }
}
