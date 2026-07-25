import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.6, specs/003-android-client.md §12.4 — the privacy settings hub:
/// Export (all users) / Delete account (all users) / Delete family (parents only) — `isParent`
/// gates whether the "Delete family" entry is even shown.
@MainActor
struct PrivacySettingsViewModelTests {

    @Test func load_parent_setsIsParentTrue() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
        let viewModel = PrivacySettingsViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(isParent: true))
    }

    @Test func load_member_setsIsParentFalse() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u2", role: "member"), members: []
            ))
        }
        let viewModel = PrivacySettingsViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(isParent: false))
    }

    /// specs/008-privacy-endpoints.md §4.4 — export/delete-account MUST be reachable regardless of
    /// family state; a family-less caller just doesn't get the "Delete family" entry.
    @Test func load_familyLess_stillLoadedWithIsParentFalse() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = PrivacySettingsViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(isParent: false))
    }

    @Test func load_otherFailure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        let viewModel = PrivacySettingsViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
