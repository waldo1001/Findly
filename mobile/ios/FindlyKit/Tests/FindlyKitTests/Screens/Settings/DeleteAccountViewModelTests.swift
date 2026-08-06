import Foundation
import Testing
@testable import FindlyKit

/// A call-counting `wipeLocalState` test double — mirrors `LocationRuntimeContainer.wipeLocalState()`
/// (security review addition) without needing a real container/CLLocationManager/SQLite stack in
/// these tests; `LocationRuntimeContainerTests` owns proving what the real method actually clears.
private final class WipeLocalStateRecorder {
    private(set) var callCount = 0
    func wipe() async { callCount += 1 }
}

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
        exportArtifactStore: InMemoryExportArtifactStore = InMemoryExportArtifactStore(),
        appVersionTracker: AppVersionRegistrationTracking = InMemoryAppVersionRegistrationTracker(),
        wipeLocalState: @escaping () async -> Void = {}
    ) -> DeleteAccountViewModel {
        DeleteAccountViewModel(
            apiClient: api, authProvider: auth, deviceIdProvider: deviceIdProvider,
            exportArtifactStore: exportArtifactStore, appVersionTracker: appVersionTracker,
            wipeLocalState: wipeLocalState
        )
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
        var deviceIdCounter = 0
        let deviceIdProvider = InMemoryDeviceIdProvider(generateUUID: {
            deviceIdCounter += 1
            return "dev-\(deviceIdCounter)"
        })
        _ = deviceIdProvider.deviceId(forUserId: "u1") // pre-register, so clearing is observable
        let exportArtifactStore = InMemoryExportArtifactStore()
        _ = try? exportArtifactStore.write(Data("leftover export".utf8))
        let recorder = WipeLocalStateRecorder()
        let viewModel = makeViewModel(
            api: api, auth: auth, deviceIdProvider: deviceIdProvider, exportArtifactStore: exportArtifactStore,
            wipeLocalState: { await recorder.wipe() }
        )

        await viewModel.confirmDelete()

        #expect(api.deleteAccountCallCount == 1)
        #expect(auth.deleteCurrentUserCallCount == 1)
        #expect(auth.clearStoredSessionCallCount == 1, "008 §1.3 (finding #5) — the Keychain-backed session is cleared as its own unconditional step")
        #expect(auth.signOutCallCount == 1)
        // Post-review (security review, High finding): DeleteAccountViewModel no longer touches
        // fixQueue/geofenceEventQueue/geofenceConfigStore directly — it calls the ONE consolidated
        // LocationRuntimeContainer.wipeLocalState() every sign-out-shaped path now shares. What
        // that method itself actually clears is proven by LocationRuntimeContainerTests.
        #expect(recorder.callCount == 1, "the account-deletion local wipe must call the consolidated wipeLocalState exactly once")
        // A fresh id is issued for "u1" now — proof the old one was actually cleared, not reused.
        #expect(deviceIdProvider.deviceId(forUserId: "u1") != "dev-1")
        #expect(exportArtifactStore.currentURL == nil, "008 §3.1 rule 2 (finding #1) — any export artifact is removed by the account-deletion wipe")
        #expect(viewModel.phase == .completed)
    }

    /// I25 (specs/008 §1.3, specs/004 §3.6) — `appVersionTracker` is what I24 made load-bearing:
    /// `DeviceRegistrationService.registerOrUpdate()` reads it to decide whether a re-registration
    /// needs to probe for a profile first. Left uncleared, a full account deletion followed by a
    /// sign-back-in on the same Firebase uid would carry a stale "this device has registered
    /// before" bit into a session that (post-deletion) genuinely has no profile — clearing it
    /// alongside `deviceIdProvider` closes that gap at the tracker's own write site, rather than
    /// depending solely on `DeviceRegistrationService`'s `PROFILE_NOT_FOUND` catch elsewhere.
    @Test func confirmDelete_success_clearsAppVersionTracker() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        let appVersionTracker = InMemoryAppVersionRegistrationTracker()
        appVersionTracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        let viewModel = makeViewModel(api: api, auth: auth, appVersionTracker: appVersionTracker)

        await viewModel.confirmDelete()

        #expect(appVersionTracker.lastRegisteredAppVersion(forUserId: "u1") == nil, "a fully torn-down account must not leave a stale 'this device already registered' bit behind")
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
        let recorder = WipeLocalStateRecorder()
        let viewModel = makeViewModel(api: api, auth: auth, wipeLocalState: { await recorder.wipe() })

        await viewModel.confirmDelete()

        #expect(viewModel.phase == .firebaseDeleteFailed)
        #expect(recorder.callCount == 0, "local state must survive an unrecovered Firebase-delete failure")
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

        await viewModel.signOutForRetry()

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

        await viewModel.signOutForRetry()

        #expect(auth.clearStoredSessionCallCount == 1)
        #expect(auth.signOutCallCount == 1)
        // The trap this replaces: NOT a bare re-invocation of the failed calls.
        #expect(api.deleteAccountCallCount == 1, "still just the one original call — sign-out-for-retry is not a backend re-call")
        #expect(auth.deleteCurrentUserCallCount == 1, "still just the one original failed attempt — no blind re-invocation")
    }

    /// **Post-review addition (security review, High finding).** Previously `signOutForRetry()`
    /// wiped nothing local at all — a real, deterministic gap: the backend account is already gone
    /// by the time this runs, but this device's registered `CLLocationManager` geofences/queued
    /// fixes/queued geofence-events/cached device settings survived untouched, so a geofence
    /// transition detected in the window before a *different* trigger happens to re-sync could get
    /// durably queued and later flushed under whichever *different* account signs in next.
    @Test func signOutForRetry_wipesLocalState() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn)
        let recorder = WipeLocalStateRecorder()
        let viewModel = makeViewModel(api: api, auth: auth, wipeLocalState: { await recorder.wipe() })
        await viewModel.confirmDelete()
        #expect(recorder.callCount == 0, "not wiped yet — only the Firebase step has failed so far")

        await viewModel.signOutForRetry()

        #expect(recorder.callCount == 1)
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
        await viewModel.signOutForRetry()

        #expect(auth.clearStoredSessionCallCount == 1, "must run even though signOut() below it failed")
        #expect(viewModel.phase == .signedOutForRetry, "the screen still navigates to sign-in — there is nothing else to offer")
    }

    /// I25 — `appVersionTracker` joins `deviceIdProvider`/`exportArtifactStore` in the "deliberately
    /// left alone here" category this type's top doc already establishes for `signOutForRetry()`:
    /// all three are per-account-identity state that is only meaningful to clear once
    /// `wipeLocalStateAndComplete()` confirms the account is FULLY torn down, including client-side
    /// (i.e. the Firebase step also succeeded). Clearing any of them earlier — on a Firebase-delete
    /// failure that hasn't been retried yet — would not be wrong today (the backend account really
    /// is already gone by this point), but it would split "account teardown" bookkeeping across two
    /// call sites for no behavioral gain, since a successful retry reaches
    /// `wipeLocalStateAndComplete()` and clears them anyway.
    @Test func signOutForRetry_doesNotClearDeviceIdOrAppVersionTracker() async {
        let api = FakeAPIClient()
        api.deleteAccountHandler = {}
        let auth = FakeAuthProviding()
        auth.currentUserId = "u1"
        auth.deleteCurrentUserResult = .failure(AuthError.notSignedIn)
        let deviceIdProvider = InMemoryDeviceIdProvider()
        let existingDeviceId = deviceIdProvider.deviceId(forUserId: "u1")
        let appVersionTracker = InMemoryAppVersionRegistrationTracker()
        appVersionTracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        let viewModel = makeViewModel(
            api: api, auth: auth, deviceIdProvider: deviceIdProvider, appVersionTracker: appVersionTracker
        )
        await viewModel.confirmDelete()

        await viewModel.signOutForRetry()

        #expect(deviceIdProvider.deviceId(forUserId: "u1") == existingDeviceId, "deviceIdProvider is only cleared by wipeLocalStateAndComplete()")
        #expect(appVersionTracker.lastRegisteredAppVersion(forUserId: "u1") == "1.0.0", "appVersionTracker is only cleared by wipeLocalStateAndComplete()")
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
