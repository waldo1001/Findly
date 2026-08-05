import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §12.6) — join a group from a pasted code or the
/// `findly://group-join?code=…` deep link. Every input is normalized/validated by `GroupCodeParsing`
/// BEFORE the network call (security checklist §5 — deep-link inputs validated before use).
@MainActor
struct GroupJoinViewModelTests {

    /// A profile-exists `getMyFamily()` stub — used by every test below that submits a blank
    /// `displayName` and expects the call to proceed, since `join` now probes `GET /families/me`
    /// (I17 review, Major fix) whenever `displayName` is blank.
    private static func profileExistsHandler() -> () async throws -> Envelope<GetMyFamilyResponse> {
        {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
    }

    @Test func initialState_isIdle() {
        let viewModel = GroupJoinViewModel(apiClient: FakeAPIClient())
        #expect(viewModel.state == .idle)
    }

    @Test func join_malformedCode_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "not-a-code", displayName: "Noor")

        #expect(api.joinGroupCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_deepLinkCode_isNormalizedBeforeSending() async {
        let api = FakeAPIClient()
        api.joinGroupHandler = { code, displayName in
            #expect(code == "7F3K9QRZ")
            #expect(displayName == "Noor")
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_x", name: "Festival crew", endsAt: "2026-08-02T22:00:00Z",
                expiryPolicy: "delete", state: "active", role: "member", memberCount: 8,
                code: "7F3K9QRZ", createdAt: nil
            ))
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "findly://group-join?code=7f3k9qrz", displayName: "Noor")

        #expect(viewModel.state == .joined(GroupSummary(
            groupId: "grp_x", name: "Festival crew", endsAt: "2026-08-02T22:00:00Z",
            expiryPolicy: "delete", state: "active", role: "member", memberCount: 8,
            code: "7F3K9QRZ", createdAt: nil
        )))
    }

    @Test func join_nonBlankDisplayName_neverProbesProfile() async {
        // The probe is only needed to resolve an ambiguous blank name — skip it entirely when a
        // name was actually given.
        let api = FakeAPIClient()
        api.joinGroupHandler = { code, displayName in
            TestFeatures.envelope(GroupSummary(
                groupId: "grp_x", name: "Crew", endsAt: "2026-08-02T22:00:00Z", expiryPolicy: "delete",
                state: "active", role: "member", memberCount: 2, code: code, createdAt: nil
            ))
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "Noor")

        #expect(api.getMyFamilyCallCount == 0)
        guard case .joined = viewModel.state else {
            Issue.record("expected .joined state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - I17 review (Major fix, specs/001 §12.6: "displayName REQUIRED then, optional
    // otherwise") — whether this call is bootstrapping a profile is established from the server's
    // own truth (a `GET /families/me` probe run only when `displayName` is blank), NOT from a
    // caller-supplied flag. This screen is the app's primary external on-ramp (specs/005/007's
    // `findly://group-join`/https join links) — `AppCoordinator.handleDeepLink` routes straight to
    // `.groupJoin`, so a `RootView`-level "which Home button was tapped" flag is never set for this
    // arrival at all. Constructing the view model with no special setup — exactly as a deep-link
    // arrival would (`RootView`'s `.groupJoin` case now always constructs a plain
    // `GroupJoinViewModel(apiClient:)` regardless of route) — and relying purely on the profile
    // probe below IS the regression coverage for that gap.

    @Test func join_arrivedViaDeepLinkStyleBlankDisplayNameAndNoProfile_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        // No `needsDisplayName`-style setup at all — this is exactly the shape a
        // `findly://group-join?code=…` deep-link arrival constructs the view model with.
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "findly://group-join?code=7f3k9qrz", displayName: "   ")

        #expect(api.joinGroupCalls.isEmpty)
        #expect(api.getMyFamilyCallCount == 1)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_blankDisplayNameAndProfileExists_sendsNilNotEmptyString() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = Self.profileExistsHandler()
        api.joinGroupHandler = { code, displayName in
            #expect(displayName == nil)
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_x", name: "Crew", endsAt: "2026-08-02T22:00:00Z", expiryPolicy: "delete",
                state: "active", role: "member", memberCount: 2, code: code, createdAt: nil
            ))
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "   ")

        guard case .joined = viewModel.state else {
            Issue.record("expected .joined state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_blankDisplayNameAndInconclusiveProbe_defaultsToNotBootstrappingAndProceeds() async {
        // A transport blip on the probe must never strand an ordinary caller — default to NOT
        // requiring a name; the server still enforces it if this default is ever wrong.
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        api.joinGroupHandler = { code, displayName in
            #expect(displayName == nil)
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_x", name: "Crew", endsAt: "2026-08-02T22:00:00Z", expiryPolicy: "delete",
                state: "active", role: "member", memberCount: 2, code: code, createdAt: nil
            ))
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "   ")

        guard case .joined = viewModel.state else {
            Issue.record("expected .joined state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_rotatedOrUnknownCode_setsErrorState() async {
        let api = FakeAPIClient()
        api.joinGroupHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .groupCodeInvalid, message: "invalid", details: nil, requestId: "r1"), httpStatus: 400)
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "Noor")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_alreadyMember_setsErrorState() async {
        let api = FakeAPIClient()
        api.joinGroupHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .groupAlreadyMember, message: "already", details: nil, requestId: "r1"), httpStatus: 409)
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "Noor")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_groupFull_setsErrorState() async {
        let api = FakeAPIClient()
        api.joinGroupHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .groupFull, message: "full", details: ["max": .number(50)], requestId: "r1"), httpStatus: 409)
        }
        let viewModel = GroupJoinViewModel(apiClient: api)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "Noor")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
