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
}
