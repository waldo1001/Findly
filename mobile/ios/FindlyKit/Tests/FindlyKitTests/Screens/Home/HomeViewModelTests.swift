import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 — the post-sign-in hub's family-context load.
@MainActor
struct HomeViewModelTests {

    @Test func load_success_excludesSelfFromOtherMembers() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:01:00Z"),
                ]
            ))
        }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        guard case .loaded(let myUserId, let isParent, let familyName, let otherMembers) = viewModel.state else {
            Issue.record("expected .loaded state, got \(viewModel.state)")
            return
        }
        #expect(myUserId == "u1")
        #expect(isParent == true)
        #expect(familyName == "Wauters")
        #expect(otherMembers.map(\.userId) == ["u2"])
    }

    @Test func load_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - Family-less (review-gate finding #3, specs/005 §1, 001 §1.5) — a signed-in user
    // without a family is first-class, not a dead end: `FAMILY_NOT_FOUND`/`PROFILE_NOT_FOUND` on
    // the family fetch must land in a distinct, renderable state (not the generic `.error`), so
    // `HomeScreen` can still offer Groups — the one destination that works without a family.

    @Test func load_familyNotFound_setsFamilylessState() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .familyless)
    }

    @Test func load_profileNotFound_setsFamilylessState() async {
        // A brand-new signed-in user with no profile at all yet (001 §1.5.3) is likewise
        // family-less, not a dead end — same rendering as FAMILY_NOT_FOUND.
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .familyless)
    }

    @Test func load_otherServerError_staysGenericError() async {
        // Only the two family-less-signalling codes get the special state — everything else
        // (incl. other 4xx/5xx codes) keeps the existing generic error rendering.
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .internalError, message: "boom", details: nil, requestId: "r1"), httpStatus: 500)
        }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
