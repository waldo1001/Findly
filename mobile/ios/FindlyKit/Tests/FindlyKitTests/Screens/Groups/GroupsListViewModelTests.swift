import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §12.2) — the groups list; also the screen a family-less
/// signed-in user (`FAMILY_NOT_FOUND`/`PROFILE_NOT_FOUND` on family calls, 001 §1.5) can reach as a
/// non-dead-end destination, so its loaded-but-empty state must offer create/join, not just an
/// empty list (covered by the screen, not this view model).
@MainActor
struct GroupsListViewModelTests {

    @Test func initialState_isLoading() {
        let viewModel = GroupsListViewModel(apiClient: FakeAPIClient())
        #expect(viewModel.state == .loading)
    }

    @Test func load_success_populatesState() async {
        let api = FakeAPIClient()
        api.listGroupsHandler = {
            TestFeatures.envelope(ListGroupsResponse(groups: [
                GroupSummary(
                    groupId: "grp_1", name: "Festival crew", endsAt: "2026-08-02T22:00:00Z",
                    expiryPolicy: "delete", state: "active", role: "owner", memberCount: 7,
                    code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
                )
            ]))
        }
        let viewModel = GroupsListViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded([
            GroupSummary(
                groupId: "grp_1", name: "Festival crew", endsAt: "2026-08-02T22:00:00Z",
                expiryPolicy: "delete", state: "active", role: "owner", memberCount: 7,
                code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
            )
        ]))
    }

    @Test func load_emptyList_isNotAnError() async {
        // A family-less brand-new user's first `GET /groups` — must resolve to `.loaded([])`, the
        // screen's job to render as a friendly non-dead-end empty state, not `.error`.
        let api = FakeAPIClient()
        api.listGroupsHandler = { TestFeatures.envelope(ListGroupsResponse(groups: [])) }
        let viewModel = GroupsListViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded([]))
    }

    @Test func load_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.listGroupsHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = GroupsListViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
