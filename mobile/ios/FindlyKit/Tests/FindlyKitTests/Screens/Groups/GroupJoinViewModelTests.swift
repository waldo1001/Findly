import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §12.6) — join a group from a pasted code or the
/// `findly://group-join?code=…` deep link. Every input is normalized/validated by `GroupCodeParsing`
/// BEFORE the network call (security checklist §5 — deep-link inputs validated before use).
@MainActor
struct GroupJoinViewModelTests {

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

    @Test func join_blankDisplayName_sendsNilNotEmptyString() async {
        let api = FakeAPIClient()
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

    // MARK: - I17 bootstrap guard (001 §12.6: "displayName REQUIRED then, optional otherwise") —
    // `needsDisplayName` is threaded in from the profile-less first-run flow
    // (`HomeViewModel.State.profileless`); a blank display name must never reach the network in
    // that case.

    @Test func join_needsDisplayNameAndBlank_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = GroupJoinViewModel(apiClient: api, needsDisplayName: true)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "   ")

        #expect(api.joinGroupCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func join_needsDisplayNameAndProvided_callsTheApi() async {
        let api = FakeAPIClient()
        api.joinGroupHandler = { code, displayName in
            #expect(displayName == "Noor")
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_x", name: "Crew", endsAt: "2026-08-02T22:00:00Z", expiryPolicy: "delete",
                state: "active", role: "member", memberCount: 2, code: code, createdAt: nil
            ))
        }
        let viewModel = GroupJoinViewModel(apiClient: api, needsDisplayName: true)

        await viewModel.join(rawCode: "7F3K9QRZ", displayName: "Noor")

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
