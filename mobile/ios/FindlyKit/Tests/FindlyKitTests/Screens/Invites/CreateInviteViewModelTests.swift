import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §3.3).
@MainActor
struct CreateInviteViewModelTests {

    @Test func createInvite_success_transitionsToCreated() async {
        let api = FakeAPIClient()
        api.createInviteHandler = { role, emailHint in
            #expect(role == "member")
            #expect(emailHint == "kid@example.com")
            return TestFeatures.envelope(CreateInviteResponse(inviteCode: "7F3K9QRZ", role: "member", expiresAt: "2026-07-22T10:00:00Z"))
        }
        let viewModel = CreateInviteViewModel(apiClient: api)

        await viewModel.createInvite(role: "member", emailHint: "kid@example.com")

        #expect(viewModel.state == .created(inviteCode: "7F3K9QRZ", role: "member", expiresAt: "2026-07-22T10:00:00Z"))
    }

    @Test func createInvite_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.createInviteHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .authForbidden, message: "not a parent", details: nil, requestId: "r1"), httpStatus: 403)
        }
        let viewModel = CreateInviteViewModel(apiClient: api)

        await viewModel.createInvite(role: "member", emailHint: nil)

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func shareText_formatsCodeAsHyphenatedGroups() {
        #expect(CreateInviteViewModel.shareText(for: "7f3k9qrz").contains("7F3K-9QRZ"))
    }
}
