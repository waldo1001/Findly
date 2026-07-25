import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §5 — family deletion: parent-only,
/// names the irreversible loss of the whole family's history, and confirmation gating (no
/// destructive call before the explicit confirm).
@MainActor
struct DeleteFamilyViewModelTests {

    @Test func load_success_populatesFamilyName() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
        let viewModel = DeleteFamilyViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.phase == .ready(familyName: "Wauters"))
    }

    @Test func load_failure_setsErrorPhase() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = DeleteFamilyViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.phase else {
            Issue.record("expected .error phase, got \(viewModel.phase)")
            return
        }
    }

    @Test func load_neverCallsDeleteFamily() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
        let viewModel = DeleteFamilyViewModel(apiClient: api)

        await viewModel.load()

        #expect(api.deleteFamilyCallCount == 0)
    }

    @Test func confirmDelete_success_callsDeleteFamilyAndCompletes() async {
        let api = FakeAPIClient()
        api.deleteFamilyHandler = {}
        let viewModel = DeleteFamilyViewModel(apiClient: api)

        await viewModel.confirmDelete()

        #expect(api.deleteFamilyCallCount == 1)
        #expect(viewModel.phase == .completed)
    }

    @Test func confirmDelete_forbidden_setsErrorPhase() async {
        let api = FakeAPIClient()
        api.deleteFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .authForbidden, message: "x", details: nil, requestId: "r1"), httpStatus: 403)
        }
        let viewModel = DeleteFamilyViewModel(apiClient: api)

        await viewModel.confirmDelete()

        guard case .error = viewModel.phase else {
            Issue.record("expected .error phase, got \(viewModel.phase)")
            return
        }
    }

    /// specs/008-privacy-endpoints.md §5.4 — names the irreversible whole-family loss.
    @Test func confirmationMessage_namesTheWholeFamilyIrreversibleLoss() {
        let message = DeleteFamilyViewModel.confirmationMessage(familyName: "Wauters")
        #expect(message.contains("Wauters"))
        #expect(message.lowercased().contains("everyone") || message.lowercased().contains("every member") || message.lowercased().contains("all members"))
        #expect(message.lowercased().contains("can't be undone") || message.lowercased().contains("cannot be undone") || message.lowercased().contains("irreversib"))
    }
}
