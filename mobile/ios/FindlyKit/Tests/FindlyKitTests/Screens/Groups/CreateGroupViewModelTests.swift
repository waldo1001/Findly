import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §12.1; 005 §2.1) — group creation. `displayName` is always
/// sent as either a trimmed value or `nil` (never an empty string) since the server treats it as
/// REQUIRED-only-if-bootstrapping/optional-otherwise (001 §12.1) — this client doesn't need to know
/// which case applies, it just never sends a blank string standing in for absence.
@MainActor
struct CreateGroupViewModelTests {

    @Test func initialState_isIdle() {
        let viewModel = CreateGroupViewModel(apiClient: FakeAPIClient())
        #expect(viewModel.state == .idle)
    }

    @Test func createGroup_emptyName_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "   ", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .delete, displayName: "Eric")

        #expect(api.createGroupCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func createGroup_success_sendsTrimmedFieldsAndFormattedEndsAt() async {
        let api = FakeAPIClient()
        let endsAt = ISO8601DateFormatter().date(from: "2026-08-02T22:00:00Z")!
        api.createGroupHandler = { name, endsAtString, expiryPolicy, displayName in
            #expect(name == "Festival crew")
            #expect(endsAtString == "2026-08-02T22:00:00Z")
            #expect(expiryPolicy == "delete")
            #expect(displayName == "Eric")
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_9J2Kq7Lm3NpR5sTvWxYz", name: "Festival crew", endsAt: "2026-08-02T22:00:00Z",
                expiryPolicy: "delete", state: "active", role: "owner", memberCount: 1,
                code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
            ))
        }
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "  Festival crew  ", endsAt: endsAt, expiryPolicy: .delete, displayName: "  Eric  ")

        #expect(viewModel.state == .created(GroupSummary(
            groupId: "grp_9J2Kq7Lm3NpR5sTvWxYz", name: "Festival crew", endsAt: "2026-08-02T22:00:00Z",
            expiryPolicy: "delete", state: "active", role: "owner", memberCount: 1,
            code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
        )))
    }

    @Test func createGroup_blankDisplayName_sendsNilNotEmptyString() async {
        let api = FakeAPIClient()
        api.createGroupHandler = { name, endsAtString, expiryPolicy, displayName in
            #expect(displayName == nil)
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_1", name: name, endsAt: endsAtString, expiryPolicy: expiryPolicy,
                state: "active", role: "owner", memberCount: 1, code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
            ))
        }
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .grace, displayName: "   ")

        guard case .created = viewModel.state else {
            Issue.record("expected .created state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - I17 bootstrap guard (001 §12.1: "displayName REQUIRED then, optional otherwise") —
    // `needsDisplayName` is threaded in from the profile-less first-run flow
    // (`HomeViewModel.State.profileless`); a blank display name must never reach the network in
    // that case, same "gate before any network call" convention as `CreateFamilyViewModel`/
    // `AcceptInviteViewModel`.

    @Test func createGroup_needsDisplayNameAndBlank_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = CreateGroupViewModel(apiClient: api, needsDisplayName: true)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .delete, displayName: "   ")

        #expect(api.createGroupCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func createGroup_needsDisplayNameAndProvided_callsTheApi() async {
        let api = FakeAPIClient()
        api.createGroupHandler = { name, endsAtString, expiryPolicy, displayName in
            #expect(displayName == "Eric")
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_1", name: name, endsAt: endsAtString, expiryPolicy: expiryPolicy,
                state: "active", role: "owner", memberCount: 1, code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
            ))
        }
        let viewModel = CreateGroupViewModel(apiClient: api, needsDisplayName: true)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .delete, displayName: "Eric")

        guard case .created = viewModel.state else {
            Issue.record("expected .created state, got \(viewModel.state)")
            return
        }
    }

    @Test func createGroup_serverError_setsErrorState() async {
        let api = FakeAPIClient()
        api.createGroupHandler = { _, _, _, _ in
            throw APIError.server(
                APIErrorBody(code: .limitExceeded, message: "limit", details: ["limit": .string("maxActiveGroups")], requestId: "r1"),
                httpStatus: 402
            )
        }
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .archive, displayName: "Eric")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
