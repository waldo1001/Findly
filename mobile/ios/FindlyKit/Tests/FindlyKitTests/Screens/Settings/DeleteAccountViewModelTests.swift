import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4 — account deletion: the
/// last-parent/sole-member cascade wording trigger (008 §4.2), the 008 §1.3 ordering
/// (`DELETE /users/me` 204 → Firebase `user.delete()` → local wipe), the sign-out-then-retry
/// recovery when the Firebase step fails (008 §1.3 — a bare retry is a trap), and confirmation
/// gating (no destructive call fires merely from `load()`).
@MainActor
struct DeleteAccountViewModelTests {

    func makeFamily(me: MeSummary, members: [FamilyMember]) -> GetMyFamilyResponse {
        GetMyFamilyResponse(familyId: "fam_1", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z", me: me, members: members)
    }

    func makeViewModel(
        api: FakeAPIClient, auth: FakeAuthProviding,
        deviceIdProvider: DeviceIdProviding = InMemoryDeviceIdProvider(),
        fixQueue: FixQueue = FixQueue(),
        exportArtifactStore: InMemoryExportArtifactStore = InMemoryExportArtifactStore()
    ) -> DeleteAccountViewModel {
        DeleteAccountViewModel(apiClient: api, authProvider: auth, deviceIdProvider: deviceIdProvider, fixQueue: fixQueue, exportArtifactStore: exportArtifactStore)
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

    // MARK: - The 008 §1.3 ordering + local wipe (review finding #1/#5 — export artifact + unconditional Keychain clear)

    @Test func confirmDelete_success_ordersBackendThenFirebaseThenWipesLocalState_thenCompletes() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        let deviceIdProvider = InMemoryDeviceIdProvider(generateUUID: { "dev-1" })
        _ = deviceIdProvider.deviceId(forUserId: "u1") // pre-register, so clearing is observable
        let fixQueue = FixQueue()
        await fixQueue.enqueue(LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic))
        let exportArtifactStore = InMemoryExportArtifactStore()
        _ = try? exportArtifactStore.write(Data("leftover export".utf8))
        let viewModel = makeViewModel(api: api, auth: auth, deviceIdProvider: deviceIdProvider, fixQueue: fixQueue, exportArtifactStore: exportArtifactStore)

        await viewModel.confirmDelete()

        #expect(api.deleteAccountCallCount == 1)
        #expect(auth.deleteCurrentUserCallCount == 1)
        #expect(auth.clearStoredSessionCallCount == 1, "008 §1.3 (finding #5) — the Keychain-backed session is cleared as its own unconditional step")
        #expect(auth.signOutCallCount == 1)
        #expect(await fixQueue.queuedCount() == 0)
        // A fresh id is issued for "u1" now — proof the old one was actually cleared, not reused.
        #expect(deviceIdProvider.deviceId(forUserId: "u1") != "dev-1")
        #expect(exportArtifactStore.currentURL == nil, "008 §3.1 rule 2 (finding #1) — any export artifact is removed by the account-deletion wipe")
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
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn) // stand-in for requires-recent-login
        let fixQueue = FixQueue()
        await fixQueue.enqueue(LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic))
        let viewModel = makeViewModel(api: api, auth: auth, fixQueue: fixQueue)

        await viewModel.confirmDelete()

        #expect(viewModel.phase == .firebaseDeleteFailed)
        #expect(await fixQueue.queuedCount() == 1, "local state must survive an unrecovered Firebase-delete failure")
        #expect(auth.signOutCallCount == 0)
        #expect(auth.clearStoredSessionCallCount == 0, "the Keychain clear is part of the wipe, which only runs once the flow actually completes")
    }

    // MARK: - Sign-out-then-retry recovery (008 §1.3, review finding #4 — a bare retry is a trap)

    @Test func signOutForRetry_isOnlyReachableAfterAFirebaseDeleteFailure() async {
        // Documents the state machine: `.ready`/`.deleting` never expose a retry path — only
        // `.firebaseDeleteFailed` does (enforced by the Screen switching on `phase`, but the
        // ViewModel method itself is safe to call in any phase, matching the rest of this
        // codebase's convention of not re-deriving guards the Screen already enforces).
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn)
        let viewModel = makeViewModel(api: api, auth: auth)

        await viewModel.confirmDelete()
        #expect(viewModel.phase == .firebaseDeleteFailed)

        viewModel.signOutForRetry()

        #expect(viewModel.phase == .signedOutForRetry)
    }

    @Test func signOutForRetry_callsClearStoredSessionAndSignOut_doesNotRecallDeleteAccountOrFirebaseDelete() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn)
        let viewModel = makeViewModel(api: api, auth: auth)
        await viewModel.confirmDelete()

        viewModel.signOutForRetry()

        #expect(auth.clearStoredSessionCallCount == 1)
        #expect(auth.signOutCallCount == 1)
        // The trap this replaces: NOT a bare re-invocation of the failed calls.
        #expect(api.deleteAccountCallCount == 1, "still just the one original call — sign-out-for-retry is not a backend re-call")
        #expect(auth.deleteCurrentUserCallCount == 1, "still just the one original failed attempt — no blind re-invocation")
    }

    /// Review finding #5 — proves the Keychain clear is genuinely unconditional: it still happens
    /// even when `signOut()` itself throws, which is exactly the scenario finding #5 flagged
    /// (`FirebaseAuthProvider` previously nested the Keychain clear inside `signOut()`'s own body).
    @Test func signOutForRetry_evenWhenSignOutThrows_stillClearsStoredSession_andTransitionsPhase() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn)
        let viewModel = makeViewModel(api: api, auth: auth)
        await viewModel.confirmDelete()

        auth.signOutResult = .failure(AuthError.notSignedIn)
        viewModel.signOutForRetry()

        #expect(auth.clearStoredSessionCallCount == 1, "must run even though signOut() below it failed")
        #expect(viewModel.phase == .signedOutForRetry, "the screen still navigates to sign-in — there is nothing else to offer")
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
