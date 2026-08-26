import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §3.4; security checklist §5 — deep-link inputs validated
/// before use).
@MainActor
struct AcceptInviteViewModelTests {

    @Test func accept_malformedCode_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "not-a-code", displayName: "Noor")

        #expect(api.acceptInviteCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func accept_emptyDisplayName_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "7F3K9QRZ", displayName: "   ")

        #expect(api.acceptInviteCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func accept_deepLinkCode_isNormalizedBeforeSending() async {
        let api = FakeAPIClient()
        api.acceptInviteHandler = { code, displayName in
            #expect(code == "7F3K9QRZ")
            #expect(displayName == "Noor")
            return TestFeatures.envelope(AcceptInviteResponse(familyId: "fam_x", familyName: "Wauters", role: "member"))
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "findly://invite/7f3k9qrz", displayName: "Noor")

        #expect(viewModel.state == .joined(familyId: "fam_x", familyName: "Wauters", role: "member"))
    }

    @Test func accept_serverError_setsErrorState() async {
        let api = FakeAPIClient()
        api.acceptInviteHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .inviteExpired, message: "expired", details: nil, requestId: "r1"), httpStatus: 410)
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.accept(rawInviteCode: "7F3K9QRZ", displayName: "Noor")

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §5.2, specs/001-api-contract.md §3.2/§4.2 —
    // prefilling the display-name field with the caller's OWN existing profile displayName, when
    // there's no Onboarding-typed name to prefill from instead. Mirrors Android's
    // loadDisplayNameFallback() test shape exactly (review fix, I37 round 2 — security Medium
    // finding): the ORIGINAL resolveExistingDisplayName() called GET /devices unconditionally and
    // adopted devices.first?.ownerDisplayName, but 001 §4.2's ownerDisplayName-equals-own-
    // displayName guarantee holds ONLY for a family-less caller — for a caller who already has a
    // family, that response carries EVERY member's devices in unspecified order, so "first" is an
    // ARBITRARY OTHER member's name. Reachable because handleDeepLink pushes .acceptInvite for a
    // family-invite link with no check of the caller's family state.

    @Test func loadDisplayNameFallback_callerHasFamily_matchesOwnUserIdAndNeverCallsListDevices() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u2", role: "member"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Sam", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:05:00Z")
                ]
            ))
        }
        // Deliberately configured (but must never be reached): if the buggy "always call
        // listDevices()" behavior were still present, this would silently adopt "Sam" (someone
        // ELSE's name) instead of failing loudly — the call-count assertion below is what
        // actually proves the branch was skipped.
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "d1", ownerUserId: "u1", platform: "ios", deviceName: "Sam's iPhone",
                    model: "iPhone14", appVersion: "1.0", syncIntervalMinutes: 15, trackingEnabled: true,
                    pushInvalid: false, ownerDisplayName: "Sam", lastSeenAt: "2026-07-19T09:05:14Z"
                )
            ]))
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.loadDisplayNameFallback()

        #expect(viewModel.resolvedDisplayName == "Noor", "must match the caller's OWN userId, never \"first member\"")
        #expect(api.listDevicesCallCount == 0, "must never call listDevices() when GET /families/me already confirms a family")
    }

    @Test func loadDisplayNameFallback_confirmedFamilyNotFound_fallsBackToListDevicesFirstEntry() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "d1", ownerUserId: "u1", platform: "ios", deviceName: "Noor's iPhone",
                    model: "iPhone15", appVersion: "1.0", syncIntervalMinutes: 15, trackingEnabled: true,
                    pushInvalid: false, ownerDisplayName: "Noor", lastSeenAt: "2026-07-19T09:05:14Z"
                )
            ]))
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.loadDisplayNameFallback()

        #expect(viewModel.resolvedDisplayName == "Noor")
        #expect(api.getMyFamilyCallCount == 1)
        #expect(api.listDevicesCallCount == 1)
    }

    @Test func loadDisplayNameFallback_ambiguousFailure_prefillsNothingAndNeverCallsListDevices() async {
        // A transient/network failure is NOT a confirmed FAMILY_NOT_FOUND — conflating the two is
        // exactly the fail-open defect 000/A37 tracks elsewhere; this must degrade to "no
        // prefill", never guess via listDevices().
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "d1", ownerUserId: "u-other", platform: "ios", deviceName: "Someone's iPhone",
                    model: "iPhone14", appVersion: "1.0", syncIntervalMinutes: 15, trackingEnabled: true,
                    pushInvalid: false, ownerDisplayName: "SomeoneElse", lastSeenAt: "2026-07-19T09:05:14Z"
                )
            ]))
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.loadDisplayNameFallback()

        #expect(viewModel.resolvedDisplayName == nil, "an ambiguous/transient outcome must never guess a name")
        #expect(api.listDevicesCallCount == 0, "must never fall back to listDevices() on anything less than a confirmed FAMILY_NOT_FOUND")
    }

    @Test func loadDisplayNameFallback_familyLessButNoDevicesYet_staysNil() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }
        api.listDevicesHandler = { TestFeatures.envelope(ListDevicesResponse(devices: [])) }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.loadDisplayNameFallback()

        #expect(viewModel.resolvedDisplayName == nil)
    }

    @Test func loadDisplayNameFallback_familyLessButListDevicesAlsoFails_staysNilWithoutThrowing() async {
        // A profile-less caller's GET /devices could itself 404 PROFILE_NOT_FOUND — this is a
        // convenience prefill, never on the join's critical path, so any failure degrades to "no
        // prefill", not an error state.
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }
        api.listDevicesHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r2"), httpStatus: 404)
        }
        let viewModel = AcceptInviteViewModel(apiClient: api)

        await viewModel.loadDisplayNameFallback()

        #expect(viewModel.resolvedDisplayName == nil)
        guard case .idle = viewModel.state else {
            Issue.record("a loadDisplayNameFallback failure must never touch join state, got \(viewModel.state)")
            return
        }
    }
}
