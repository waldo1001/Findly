import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4 — account deletion: the
/// last-parent/sole-member cascade wording trigger (008 §4.2), the 008 §1.3 ordering
/// (`DELETE /users/me` 204 → Firebase `user.delete()` → local wipe), the Firebase-failure retry
/// path, and confirmation gating (no destructive call fires merely from `load()`).
@MainActor
struct DeleteAccountViewModelTests {

    func makeFamily(me: MeSummary, members: [FamilyMember]) -> GetMyFamilyResponse {
        GetMyFamilyResponse(familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z", me: me, members: members)
    }

    func makeViewModel(api: FakeAPIClient, auth: FakeAuthProviding, deviceIdProvider: DeviceIdProviding = InMemoryDeviceIdProvider(), fixQueue: FixQueue = FixQueue()) -> DeleteAccountViewModel {
        DeleteAccountViewModel(apiClient: api, authProvider: auth, deviceIdProvider: deviceIdProvider, fixQueue: fixQueue)
    }

    // MARK: - Cascade-warning detection (008 §4.2)

    @Test func load_soleMember_setsCascadeWarningTrue() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(self.makeFamily(
                me: MeSummary(userId: "u1", role: "parent"),
                members: [FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z")]
            ))
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        #expect(viewModel.phase == .ready(cascadeWarning: true))
    }

    @Test func load_lastParent_withOnlyNonParentMembers_setsCascadeWarningTrue() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(self.makeFamily(
                me: MeSummary(userId: "u1", role: "parent"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z"),
                ]
            ))
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        #expect(viewModel.phase == .ready(cascadeWarning: true))
    }

    @Test func load_coParentPresent_setsCascadeWarningFalse() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(self.makeFamily(
                me: MeSummary(userId: "u1", role: "parent"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "parent", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z"),
                ]
            ))
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        #expect(viewModel.phase == .ready(cascadeWarning: false))
    }

    @Test func load_nonParentMember_withCoParent_setsCascadeWarningFalse() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(self.makeFamily(
                me: MeSummary(userId: "u2", role: "member"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:00:00Z"),
                ]
            ))
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        #expect(viewModel.phase == .ready(cascadeWarning: false))
    }

    @Test func load_familyLess_familyNotFound_isStillReadyWithNoCascadeWarning() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        #expect(viewModel.phase == .ready(cascadeWarning: false), "a family-less user can still delete their account")
    }

    @Test func load_noProfile_profileNotFound_isStillReadyWithNoCascadeWarning() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        #expect(viewModel.phase == .ready(cascadeWarning: false), "008 §4.1 — deletion is a no-profile-safe idempotent op")
    }

    @Test func load_otherFailure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.transport("offline")
        }
        let viewModel = makeViewModel(api: api, auth: FakeAuthProviding())

        await viewModel.load()

        guard case .error = viewModel.phase else {
            Issue.record("expected .error phase, got \(viewModel.phase)")
            return
        }
    }

    // MARK: - Confirmation gating (no destructive call before the explicit confirm)

    @Test func load_neverCallsDeleteAccountOrFirebaseDelete() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { TestFeatures.envelope(self.makeFamily(me: MeSummary(userId: "u1", role: "parent"), members: [])) }
        let auth = FakeAuthProviding()
        let viewModel = makeViewModel(api: api, auth: auth)

        await viewModel.load()

        #expect(api.deleteAccountCallCount == 0)
        #expect(auth.deleteCurrentUserCallCount == 0)
    }

    // MARK: - The 008 §1.3 ordering + local wipe

    @Test func confirmDelete_success_ordersBackendThenFirebaseThenWipesLocalState_thenCompletes() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        let deviceIdProvider = InMemoryDeviceIdProvider(generateUUID: { "dev-1" })
        _ = deviceIdProvider.deviceId(forUserId: "u1") // pre-register, so clearing is observable
        let fixQueue = FixQueue()
        await fixQueue.enqueue(LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic))
        let viewModel = makeViewModel(api: api, auth: auth, deviceIdProvider: deviceIdProvider, fixQueue: fixQueue)

        await viewModel.confirmDelete()

        #expect(api.deleteAccountCallCount == 1)
        #expect(auth.deleteCurrentUserCallCount == 1)
        #expect(auth.signOutCallCount == 1, "signOut() is what wipes the Keychain-backed verificationID, per FirebaseAuthProvider")
        #expect(await fixQueue.queuedCount() == 0)
        // A fresh id is issued for "u1" now — proof the old one was actually cleared, not reused.
        #expect(deviceIdProvider.deviceId(forUserId: "u1") != "dev-1")
        #expect(viewModel.phase == .completed)
    }

    @Test func confirmDelete_backendFailure_setsErrorPhase_neverCallsFirebaseDelete() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = { throw APIError.transport("offline") }
        let auth = FakeAuthProviding()
        let viewModel = makeViewModel(api: api, auth: auth)

        await viewModel.confirmDelete()

        guard case .error = viewModel.phase else {
            Issue.record("expected .error phase, got \(viewModel.phase)")
            return
        }
        #expect(auth.deleteCurrentUserCallCount == 0)
    }

    @Test func confirmDelete_firebaseDeleteFails_setsFirebaseDeleteFailedPhase_doesNotWipeLocalState() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn) // stand-in for "requires recent login"
        let fixQueue = FixQueue()
        await fixQueue.enqueue(LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic))
        let viewModel = makeViewModel(api: api, auth: auth, fixQueue: fixQueue)

        await viewModel.confirmDelete()

        #expect(viewModel.phase == .firebaseDeleteFailed)
        #expect(await fixQueue.queuedCount() == 1, "local state must survive an unrecovered Firebase-delete failure")
        #expect(auth.signOutCallCount == 0)
    }

    @Test func retryFirebaseDelete_afterFailure_succeeds_doesNotRecallBackendDelete_andCompletes() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn)
        let viewModel = makeViewModel(api: api, auth: auth)

        await viewModel.confirmDelete()
        #expect(viewModel.phase == .firebaseDeleteFailed)

        auth.deleteCurrentUserResult = .success(())
        await viewModel.retryFirebaseDelete()

        #expect(api.deleteAccountCallCount == 1, "the backend call is idempotent but the retry path should not blindly re-fire it")
        #expect(auth.deleteCurrentUserCallCount == 2)
        #expect(viewModel.phase == .completed)
    }

    // MARK: - Cascade wording (008 §4.2)

    @Test func confirmationMessage_cascadeWarning_mentionsOnlyParentAndFamily() {
        let message = DeleteAccountViewModel.confirmationMessage(cascadeWarning: true)
        #expect(message.lowercased().contains("only parent"))
        #expect(message.lowercased().contains("family"))
    }

    @Test func confirmationMessage_noCascadeWarning_omitsTheFamilyWideClaim() {
        let message = DeleteAccountViewModel.confirmationMessage(cascadeWarning: false)
        #expect(!message.lowercased().contains("only parent"))
    }
}
