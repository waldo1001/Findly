import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §12.1; 005 §2.1) — group creation. `displayName` is always
/// sent as either a trimmed value or `nil` (never an empty string) since the server treats it as
/// REQUIRED-only-if-bootstrapping/optional-otherwise (001 §12.1) — this client doesn't need to know
/// which case applies, it just never sends a blank string standing in for absence.
@MainActor
struct CreateGroupViewModelTests {

    /// A profile-exists `getMyFamily()` stub — used by every test below that submits a blank
    /// `displayName` and expects the call to proceed, since `createGroup` now probes
    /// `GET /families/me` (I17 review, Major fix) whenever `displayName` is blank.
    private static func profileExistsHandler() -> () async throws -> Envelope<GetMyFamilyResponse> {
        {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
    }

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

    @Test func createGroup_nonBlankDisplayName_neverProbesProfile() async {
        // The probe is only needed to resolve an ambiguous blank name — skip it entirely when a
        // name was actually given, so the ordinary (already-has-a-profile) path never pays for an
        // extra round trip.
        let api = FakeAPIClient()
        api.createGroupHandler = { name, endsAtString, expiryPolicy, displayName in
            TestFeatures.envelope(GroupSummary(
                groupId: "grp_1", name: name, endsAt: endsAtString, expiryPolicy: expiryPolicy,
                state: "active", role: "owner", memberCount: 1, code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
            ))
        }
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .delete, displayName: "Eric")

        #expect(api.getMyFamilyCallCount == 0)
        guard case .created = viewModel.state else {
            Issue.record("expected .created state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - I17 review (Major fix, specs/001 §12.1: "displayName REQUIRED then, optional
    // otherwise") — whether this call is bootstrapping a profile is established from the server's
    // own truth (a `GET /families/me` probe run only when `displayName` is blank), NOT from a
    // caller-supplied flag. The pre-fix shape threaded a `needsDisplayName` flag in from
    // `RootView`, set only by the profile-less Home closures — wrong for any arrival that doesn't
    // go through those closures, most notably a `findly://group-join`-style deep link
    // (`AppCoordinator.handleDeepLink` routes directly, never touching that flag). Constructing the
    // view model with no special setup — exactly as a deep-link arrival would — and relying purely
    // on the profile probe is itself the regression coverage for that gap.

    @Test func createGroup_blankDisplayNameAndNoProfile_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .delete, displayName: "   ")

        #expect(api.createGroupCalls.isEmpty)
        #expect(api.getMyFamilyCallCount == 1)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func createGroup_blankDisplayNameAndProfileExists_sendsNilNotEmptyString() async {
        // A signed-in caller with a profile but no family (or a family) leaving the per-group
        // nickname blank — 001 §12.1 defaults it to the profile's own displayName server-side.
        let api = FakeAPIClient()
        api.getMyFamilyHandler = Self.profileExistsHandler()
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

    @Test func createGroup_blankDisplayNameAndInconclusiveProbe_defaultsToNotBootstrappingAndProceeds() async {
        // A transport blip on the probe must never strand an ordinary caller behind an incorrect
        // "Enter a display name" wall — default to NOT requiring it; if this default is ever wrong,
        // the server itself still enforces the requirement (VALIDATION_FAILED, details.fields).
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        api.createGroupHandler = { name, endsAtString, expiryPolicy, displayName in
            #expect(displayName == nil)
            return TestFeatures.envelope(GroupSummary(
                groupId: "grp_1", name: name, endsAt: endsAtString, expiryPolicy: expiryPolicy,
                state: "active", role: "owner", memberCount: 1, code: "7F3K9QRZ", createdAt: "2026-07-21T10:00:00Z"
            ))
        }
        let viewModel = CreateGroupViewModel(apiClient: api)

        await viewModel.createGroup(name: "Crew", endsAt: Date().addingTimeInterval(86400), expiryPolicy: .delete, displayName: "   ")

        guard case .created = viewModel.state else {
            Issue.record("expected .created state, got \(viewModel.state)")
            return
        }
    }

    @Test func createGroup_serverError_setsErrorState() async {
        // displayName is non-blank, so this never probes getMyFamily (see
        // createGroup_nonBlankDisplayName_neverProbesProfile above).
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
