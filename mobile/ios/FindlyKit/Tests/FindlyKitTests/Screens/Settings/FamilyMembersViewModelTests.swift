import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §3.2, §3.5–3.6) — family roster + member management,
/// parent-only mutations derived from the server's own `me.role`.
@MainActor
struct FamilyMembersViewModelTests {

    func makeFamilyEnvelope(myRole: String = "parent") -> Envelope<GetMyFamilyResponse> {
        TestFeatures.envelope(GetMyFamilyResponse(
            familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
            me: MeSummary(userId: "u1", role: myRole),
            members: [
                FamilyMember(userId: "u1", role: myRole, displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:01:00Z"),
            ]
        ))
    }

    @Test func load_asParent_derivesIsParentTrue() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope(myRole: "parent") }
        let viewModel = FamilyMembersViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.isParent == true)
    }

    @Test func load_asMember_derivesIsParentFalse() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope(myRole: "member") }
        let viewModel = FamilyMembersViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.isParent == false)
    }

    @Test func updateRole_asParent_updatesTheMatchingMemberInPlace() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope() }
        api.updateMemberHandler = { userId, role, _ in
            #expect(userId == "u2")
            #expect(role == "parent")
            return TestFeatures.envelope(FamilyMember(userId: "u2", role: "parent", displayName: "Noor", joinedAt: "2026-07-19T08:01:00Z"))
        }
        let viewModel = FamilyMembersViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.updateRole(userId: "u2", role: "parent")

        guard case .loaded(_, _, let members) = viewModel.state else {
            Issue.record("expected .loaded state")
            return
        }
        #expect(members.first { $0.userId == "u2" }?.role == "parent")
        #expect(viewModel.lastActionError == nil)
    }

    @Test func remove_asNonParent_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope(myRole: "member") }
        let viewModel = FamilyMembersViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.remove(userId: "u2")

        #expect(api.removeMemberCalls.isEmpty)
        #expect(viewModel.lastActionError != nil)
    }

    @Test func remove_asParent_removesTheMemberFromTheList() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope() }
        api.removeMemberHandler = { userId in #expect(userId == "u2") }
        let viewModel = FamilyMembersViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.remove(userId: "u2")

        guard case .loaded(_, _, let members) = viewModel.state else {
            Issue.record("expected .loaded state")
            return
        }
        #expect(members.map(\.userId) == ["u1"])
    }

    @Test func remove_lastParentRejection_surfacesErrorWithoutMutatingList() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope() }
        api.removeMemberHandler = { _ in
            throw APIError.server(APIErrorBody(code: .validationFailed, message: "last parent", details: nil, requestId: "r1"), httpStatus: 400)
        }
        let viewModel = FamilyMembersViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.remove(userId: "u1")

        #expect(viewModel.lastActionError != nil)
        guard case .loaded(_, _, let members) = viewModel.state else {
            Issue.record("expected .loaded state")
            return
        }
        #expect(members.map(\.userId) == ["u1", "u2"])
    }

    // MARK: - Self-management (review-gate finding #2) — §3.5/§3.6 only forbid self-demotion/
    // self-removal for the *last* parent; otherwise the signed-in parent's own row is a legal
    // target and must actually invoke the API, not be silently no-op'd client-side.

    func makeTwoParentFamilyEnvelope() -> Envelope<GetMyFamilyResponse> {
        TestFeatures.envelope(GetMyFamilyResponse(
            familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
            me: MeSummary(userId: "u1", role: "parent"),
            members: [
                FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                FamilyMember(userId: "u2", role: "parent", displayName: "Noor", joinedAt: "2026-07-19T08:01:00Z"),
            ]
        ))
    }

    @Test func updateRole_onOwnRow_whenAnotherParentExists_stepsDownSuccessfully() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeTwoParentFamilyEnvelope() }
        api.updateMemberHandler = { userId, role, _ in
            #expect(userId == "u1")
            #expect(role == "member")
            return TestFeatures.envelope(FamilyMember(userId: "u1", role: "member", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"))
        }
        let viewModel = FamilyMembersViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.updateRole(userId: "u1", role: "member")

        #expect(api.updateMemberCalls.count == 1)
        #expect(viewModel.lastActionError == nil)
        guard case .loaded(_, _, let members) = viewModel.state else {
            Issue.record("expected .loaded state")
            return
        }
        #expect(members.first { $0.userId == "u1" }?.role == "member")
    }

    @Test func remove_onOwnRow_whenAnotherParentExists_leavesTheFamilySuccessfully() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeTwoParentFamilyEnvelope() }
        api.removeMemberHandler = { userId in #expect(userId == "u1") }
        let viewModel = FamilyMembersViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.remove(userId: "u1")

        #expect(api.removeMemberCalls == ["u1"])
        #expect(viewModel.lastActionError == nil)
        guard case .loaded(_, _, let members) = viewModel.state else {
            Issue.record("expected .loaded state")
            return
        }
        #expect(members.map(\.userId) == ["u2"])
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §2.1 (I34) — the profile-dead-end routing rule.
    // `GET /families/me` is family-scoped (001 §3.2/§1.5.4).

    @Test func load_profileNotFound_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = FamilyMembersViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.profileLess))
    }

    @Test func load_familyNotFound_routesToOnboardingFamilyLess() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = FamilyMembersViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.familyLess))
    }

    // MARK: - specs/010 §1.2 — opportunistically refreshes the drawer's FamilyContextCache

    @Test func load_success_refreshesTheFamilyContextCache() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { self.makeFamilyEnvelope(myRole: "parent") }
        let cache = FamilyContextCache()
        let viewModel = FamilyMembersViewModel(apiClient: api, familyContextCache: cache)

        await viewModel.load()

        #expect(cache.familyName == "Wauters")
        #expect(cache.myDisplayName == "Eric")
        #expect(cache.isParent == true)
    }
}
