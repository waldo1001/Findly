import Foundation

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4 — account deletion. Reachable by
/// every signed-in user (a store requirement, 008 §4.4) regardless of family state.
///
/// **Cascade detection (008 §4.2):** `load()` fetches `GET /families/me` purely to decide whether
/// the confirmation must carry the "you are the only parent — this deletes the family for
/// everyone" wording — the caller triggers the cascade when they are the family's last parent (no
/// OTHER member is a parent) or its sole member. A family-less caller (`FAMILY_NOT_FOUND`) or one
/// with no profile yet (`PROFILE_NOT_FOUND`) has nothing to cascade and is simply `.ready` with no
/// warning — 008 §4.1 makes deletion safe (idempotent no-op) even with no profile at all.
///
/// **Ordering (008 §1.3/§4.4):** `confirmDelete()` calls `DELETE /users/me` FIRST; only on its
/// `204` does it call `authProvider.deleteCurrentUser()` (the Firebase step, app-target-implemented
/// — FindlyKit stays Firebase-SDK-free). Local state (fix queue, cached `deviceId`, the
/// Keychain-backed Firebase session, any export artifact) is wiped ONLY after BOTH steps succeed —
/// an orphaned Firebase user with erased Findly data is harmless and retryable; wiping local state
/// before the Firebase step succeeds would strand a caller who needs to retry it.
///
/// **Firebase-failure recovery (008 §1.3 — a bare retry is a trap):** `user.delete()` commonly
/// fails with `requires-recent-login`, and the backend deletion has already succeeded
/// irreversibly by then. The session is not going to become recent on its own, so re-invoking
/// `deleteCurrentUser()` unchanged would fail identically forever. The ONLY valid recovery is
/// `signOutForRetry()`: sign out (making the sign-out action reachable from the failure state
/// itself, per 008 §1.3), sign back in through the normal app flow, then re-open this screen and
/// tap Delete again — `DELETE /users/me` is an idempotent no-op by then (008 §4.1) and the now-
/// fresh session lets `user.delete()` succeed. No in-place re-authentication sub-flow is built.
/// `signOutForRetry()` also runs `wipeLocalState()` (security review addition — the backend account
/// is already gone by this point, so this device's location/geofence local state has no live
/// account to belong to either); `deviceIdProvider`/`exportArtifactStore`/`appVersionTracker`
/// (I25) are deliberately left alone here, same as before — they're only cleared once
/// `wipeLocalStateAndComplete()` confirms the account is FULLY torn down, including client-side.
@MainActor
public final class DeleteAccountViewModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case ready(cascadeWarning: Bool)
        case deleting
        /// The backend erasure succeeded but the client-side Firebase step failed — local state is
        /// deliberately NOT wiped yet. The only way out is `signOutForRetry()`.
        case firebaseDeleteFailed
        /// `signOutForRetry()` ran — the screen navigates to sign-in, same as `.completed`.
        /// Location/geofence local state WAS wiped (`wipeLocalState()`, security review addition —
        /// the backend account is already gone by this point); `deviceId`/export artifact/
        /// app-version-tracker entry (I25) were NOT (the account isn't confirmed torn down
        /// client-side yet) — the user re-opens this screen after signing back in to finish (a
        /// no-op backend call + a now-succeeding Firebase delete), at which point
        /// `wipeLocalStateAndComplete()` clears those too.
        case signedOutForRetry
        /// Both steps succeeded and local state has been wiped — the screen navigates to sign-in.
        case completed
        case error(String)
    }

    @Published public private(set) var phase: Phase = .loading

    private let apiClient: FindlyAPIClient
    private let authProvider: AuthProviding
    private let deviceIdProvider: DeviceIdProviding
    private let exportArtifactStore: ExportArtifactStoring
    /// specs/008-privacy-endpoints.md §1.3, specs/004-ios-client.md §3.6 (I25) — I24 made this
    /// load-bearing for `DeviceRegistrationService.registerOrUpdate()`'s probe-skip decision, but
    /// this view model previously never cleared it, so a completed account deletion left a stale
    /// "this device has registered before" bit behind for the uid. Cleared alongside
    /// `deviceIdProvider` in `wipeLocalStateAndComplete()` — see that method's doc and this type's
    /// top doc for why NOT in `signOutForRetry()`.
    private let appVersionTracker: AppVersionRegistrationTracking
    /// **Post-review addition (security review, High finding).** The single consolidated
    /// `LocationRuntimeContainer.wipeLocalState()` call, injected as a closure rather than this
    /// view model taking `fixQueue`/`geofenceEventQueue`/`geofenceConfigStore` directly (I11's
    /// original shape) — the previous shape let this view model's own wipe drift out of sync with
    /// what `LocationRuntimeContainer` actually needs to clear (it never reached
    /// `geofenceRegistrar`/`stateStore` at all), and, worse, meant this was the ONLY call site that
    /// wiped anything — sign-out (`FindlyApp.swift`'s forced `onSignedOut`) and `signOutForRetry()`
    /// below did not. One implementation (`LocationRuntimeContainer.wipeLocalState()`), three call
    /// sites, injected here as a closure the same way `onPause`/`onResume`/`onReRegisterDevice`
    /// already are elsewhere in this codebase — no default value: every call site (production and
    /// test) must consciously wire this, since a silently-absent wipe is exactly the bug this fix
    /// closes.
    private let wipeLocalState: () async -> Void
    private var pendingWipeUserId: String?

    public init(
        apiClient: FindlyAPIClient, authProvider: AuthProviding, deviceIdProvider: DeviceIdProviding,
        exportArtifactStore: ExportArtifactStoring = InMemoryExportArtifactStore(),
        appVersionTracker: AppVersionRegistrationTracking,
        wipeLocalState: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.authProvider = authProvider
        self.deviceIdProvider = deviceIdProvider
        self.exportArtifactStore = exportArtifactStore
        self.appVersionTracker = appVersionTracker
        self.wipeLocalState = wipeLocalState
    }

    public func load() async {
        phase = .loading
        do {
            let envelope = try await apiClient.getMyFamily()
            let me = envelope.data.me
            let members = envelope.data.members
            let isSoleMember = members.count == 1
            let isLastParent = me.role == "parent" && !members.contains { $0.role == "parent" && $0.userId != me.userId }
            phase = .ready(cascadeWarning: isSoleMember || isLastParent)
        } catch {
            if let code = (error as? APIError)?.serverCode, code == .familyNotFound || code == .profileNotFound {
                phase = .ready(cascadeWarning: false)
            } else {
                phase = .error(userFacingMessage(for: error))
            }
        }
    }

    public func confirmDelete() async {
        pendingWipeUserId = authProvider.currentUserId
        phase = .deleting
        do {
            try await apiClient.deleteAccount()
        } catch {
            phase = .error(userFacingMessage(for: error))
            return
        }
        do {
            try await authProvider.deleteCurrentUser()
        } catch {
            phase = .firebaseDeleteFailed
            return
        }
        await wipeLocalStateAndComplete()
    }

    /// specs/008-privacy-endpoints.md §1.3 (review finding #4) — the ONLY valid recovery from
    /// `.firebaseDeleteFailed`. Deliberately does NOT re-invoke `deleteAccount()`/
    /// `deleteCurrentUser()` — that would be the bare-retry trap this method replaces. Both calls
    /// below are best-effort: the account is already erased server-side, so there is no meaningful
    /// failure recovery left to offer if signing out itself fails — the screen still navigates to
    /// sign-in either way.
    ///
    /// **Post-review addition (security review, High finding) — now calls `wipeLocalState()`.**
    /// This path previously wiped nothing at all: the backend account is already gone by the time
    /// this runs (only the client-side Firebase step failed), but this device's local queues/caches
    /// (this user's still-registered `CLLocationManager` geofences, queued fixes/events, cached
    /// device settings) survived untouched, exactly the same deterministic leak-into-the-next-
    /// session bug the forced-sign-out path had. Now `async` (was synchronous) to await the wipe —
    /// callers use `Task { await viewModel.signOutForRetry() }` (see `DeleteAccountScreen`).
    public func signOutForRetry() async {
        await wipeLocalState()
        // clearStoredSession() is unconditional (finding #5) — NOT nested inside the swallowed
        // signOut() call below, so a signOut() failure can never strand it.
        authProvider.clearStoredSession()
        try? authProvider.signOut()
        phase = .signedOutForRetry
    }

    private func wipeLocalStateAndComplete() async {
        if let uid = pendingWipeUserId {
            deviceIdProvider.clearDeviceId(forUserId: uid)
            // I25 (specs/008 §1.3, specs/004 §3.6) — same per-uid identity bit as
            // `deviceIdProvider` above, cleared alongside it for the same reason: left stale, a
            // later sign-in on this same uid would carry a false "this device has already
            // registered" signal into `DeviceRegistrationService.registerOrUpdate()`'s probe-skip
            // decision (I24), for a user whose profile this call just erased. Harmless today only
            // because `registerOrUpdate()` separately maps a genuine `PROFILE_NOT_FOUND` from
            // `POST /devices` to the same typed error every caller already treats as expected — this
            // clears it at the tracker's own write site instead of relying solely on that.
            appVersionTracker.clearLastRegisteredAppVersion(forUserId: uid)
        }
        // Post-review change (security review, High finding) — was three separate ad-hoc clear
        // calls (fixQueue/geofenceEventQueue/geofenceConfigStore) that had already drifted out of
        // sync with what LocationRuntimeContainer actually needs to clear (geofenceRegistrar/
        // stateStore were unreachable from here). Now the same single wipe every sign-out path
        // uses — see `wipeLocalState`'s doc.
        await wipeLocalState()
        // specs/008-privacy-endpoints.md §3.1 rule 2 (finding #1) — any export artifact must not
        // survive the account it belongs to.
        exportArtifactStore.removeCurrentArtifact()
        // clearStoredSession() is unconditional (008 §1.3/finding #5) — NOT nested inside the
        // swallowed signOut() call below, so a signOut() failure can never strand it.
        authProvider.clearStoredSession()
        try? authProvider.signOut()
        phase = .completed
    }

    /// specs/008-privacy-endpoints.md §4.2 — the exact cascade consequence the confirmation MUST
    /// name when the caller is the last parent or sole member ("you are the only parent — this
    /// deletes the family for everyone"); a plain warning otherwise.
    public static func confirmationMessage(cascadeWarning: Bool) -> String {
        let base = "This permanently deletes your account and everything about it — your devices, location history, and groups. This can't be undone."
        guard cascadeWarning else { return base }
        return base + " You are the only parent, so this also deletes the family for everyone."
    }
}
