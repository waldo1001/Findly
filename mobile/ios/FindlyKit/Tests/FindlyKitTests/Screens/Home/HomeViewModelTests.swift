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

    // MARK: - Family-less vs profile-less (review-gate finding #3, specs/005 §1, 001 §1.5; I17) —
    // a signed-in user without a family is first-class, not a dead end: `FAMILY_NOT_FOUND` and
    // `PROFILE_NOT_FOUND` on the family fetch must each land in a distinct, renderable state (not
    // the generic `.error`) — but they are materially different (001 §1.5.3/§1.5.4): a
    // `FAMILY_NOT_FOUND` caller already has a `Users` profile row and can list groups (§12.2)
    // straight away, while a `PROFILE_NOT_FOUND` caller has no profile at all and cannot call
    // `GET /groups` either — only the four bootstrap endpoints work for them. I17 fixes the prior
    // conflation (both collapsed into `.familyless`), which is what made `HomeScreen.familylessContent`
    // route a profile-less caller into a `GroupsListScreen` that would itself 404.

    @Test func load_familyNotFound_setsFamilylessState() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .familyless)
    }

    @Test func load_profileNotFound_setsProfilelessState() async {
        // A brand-new signed-in user with no profile at all yet (001 §1.5.3) is a DISTINCT state
        // from family-less — see this section's doc for why.
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = HomeViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .profileless)
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
