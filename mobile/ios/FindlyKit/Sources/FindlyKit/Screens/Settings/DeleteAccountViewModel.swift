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
/// Keychain-backed Firebase session via `signOut()`) is wiped ONLY after BOTH steps succeed — an
/// orphaned Firebase user with erased Findly data is harmless and retryable; wiping local state
/// before the Firebase step succeeds would strand a caller who needs to retry it (008 §1.3 — "an
/// orphaned Firebase user ... is harmless ... the reverse orphan ... would be an erasure failure").
/// `retryFirebaseDelete()` re-attempts ONLY the Firebase step — the backend call already returned
/// `204`, and re-invoking it again is unnecessary even though 008 §4.5 confirms it would be safe.
@MainActor
public final class DeleteAccountViewModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case ready(cascadeWarning: Bool)
        case deleting
        /// The backend erasure succeeded but the client-side Firebase step failed (e.g. requires a
        /// recent sign-in, 008 §1.3) — local state is deliberately NOT wiped yet; the screen offers
        /// re-authenticate/retry per `retryFirebaseDelete()`.
        case firebaseDeleteFailed
        /// Both steps succeeded and local state has been wiped — the screen navigates to sign-in.
        case completed
        case error(String)
    }

    @Published public private(set) var phase: Phase = .loading

    private let apiClient: FindlyAPIClient
    private let authProvider: AuthProviding
    private let deviceIdProvider: DeviceIdProviding
    private let fixQueue: FixQueue
    private var pendingWipeUserId: String?

    public init(apiClient: FindlyAPIClient, authProvider: AuthProviding, deviceIdProvider: DeviceIdProviding, fixQueue: FixQueue) {
        self.apiClient = apiClient
        self.authProvider = authProvider
        self.deviceIdProvider = deviceIdProvider
        self.fixQueue = fixQueue
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
        await completeFirebaseDeleteAndWipe()
    }

    /// 008 §1.3 — "Clients MUST surface a retry path when the Firebase step fails." The backend
    /// erasure already succeeded (we only reach `.firebaseDeleteFailed` after that), so this only
    /// retries the client-side Firebase deletion, not the whole flow.
    public func retryFirebaseDelete() async {
        phase = .deleting
        await completeFirebaseDeleteAndWipe()
    }

    private func completeFirebaseDeleteAndWipe() async {
        do {
            try await authProvider.deleteCurrentUser()
        } catch {
            phase = .firebaseDeleteFailed
            return
        }
        if let uid = pendingWipeUserId {
            deviceIdProvider.clearDeviceId(forUserId: uid)
        }
        await fixQueue.clearAll()
        // signOut() is also what clears the Keychain-backed Firebase verificationID
        // (FirebaseAuthProvider, I7) — swallow any error, the account is already erased either way.
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
