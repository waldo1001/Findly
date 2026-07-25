import Foundation

/// A dev/test-only `AuthProviding`, phone-shaped per specs/006-phone-auth.md §5: `startPhoneVerification`
/// records the (already-normalized, specs/006 §3) number and immediately reports code-sent — no SMS,
/// no Firebase; `confirmCode` accepts any non-blank code and signs in with `uid` = that E.164 number
/// (the phone-shaped analogue of the previous "uid = email" dev shortcut).
///
/// Produces a **real unsigned JWT**: base64url JSON header/payload (`iss`/`aud`/`sub`/`iat`/`exp`)
/// with an empty signature segment — matching the backend's `AUTH_MODE=insecure-local`
/// (`InsecureLocalTokenVerifier`, specs/001 §2.3), which splits the token on "." and requires
/// `parts[1]` to base64url-decode to JSON with a `sub` string. The previous `"stub-header.…"` shape
/// was NOT valid base64url JSON, so the iOS dev build never actually worked against a local
/// backend — this fixes that. This type is never valid against a real Firebase-verifying backend
/// and MUST NOT be used once `FirebaseAuthProvider` (app target) is wired in (`AuthMode == .firebase`).
public final class StubAuthProvider: AuthProviding {
    public private(set) var currentUserId: String?

    private let firebaseProjectId: String
    private let now: () -> TimeInterval
    private var pendingPhoneNumber: String?
    private var tokenVersion = 0

    public init(
        currentUserId: String? = nil,
        firebaseProjectId: String = "findly-dev",
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.currentUserId = currentUserId
        self.firebaseProjectId = firebaseProjectId
        self.now = now
    }

    public func currentIDToken() async throws -> String {
        guard let uid = currentUserId else { throw AuthError.notSignedIn }
        return Self.unsignedToken(uid: uid, firebaseProjectId: firebaseProjectId, version: tokenVersion, nowSeconds: Int(now()))
    }

    public func refreshIDToken() async throws -> String {
        tokenVersion += 1
        return try await currentIDToken()
    }

    public func signOut() throws {
        currentUserId = nil
        pendingPhoneNumber = nil
    }

    /// specs/008-privacy-endpoints.md §1.3 — dev/test shape: just clears local sign-in state, like
    /// `signOut()`. The real Firebase step lives in `FirebaseAuthProvider` (app target).
    public func deleteCurrentUser() async throws {
        guard currentUserId != nil else { throw AuthError.notSignedIn }
        currentUserId = nil
        pendingPhoneNumber = nil
    }

    /// specs/008-privacy-endpoints.md §1.3 — dev/test shape: no Keychain-backed state exists here
    /// to clear, so this just mirrors `signOut()`'s local-state clear, unconditionally and without
    /// throwing.
    public func clearStoredSession() {
        pendingPhoneNumber = nil
    }

    public func startPhoneVerification(phoneNumberE164: String) async throws {
        // Defensive re-check (callers — `SignInViewModel` — are expected to already have
        // normalized the number, 006 §3): matches Android's DevAuthProvider.
        guard let normalized = PhoneNumberNormalizer.normalize(phoneNumberE164) else {
            throw PhoneAuthError.invalidPhoneNumber
        }
        pendingPhoneNumber = normalized
    }

    public func confirmCode(_ code: String) async throws {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PhoneAuthError.invalidCode
        }
        guard let phoneNumber = pendingPhoneNumber else {
            // No verification in flight (e.g. confirmCode called with no prior/expired
            // startPhoneVerification) — reads as CODE_EXPIRED, which routes the ViewModel back to
            // phone entry ("must request a new code"), matching Android's DevAuthProvider/
            // FirebaseAuthProvider (both already merged, specs/006 §5/§4.2).
            throw PhoneAuthError.codeExpired
        }
        currentUserId = phoneNumber
        pendingPhoneNumber = nil
    }

    private static func unsignedToken(uid: String, firebaseProjectId: String, version: Int, nowSeconds: Int) -> String {
        let header = #"{"alg":"none","typ":"JWT"}"#
        let payload = """
        {"iss":"https://securetoken.google.com/\(firebaseProjectId)","aud":"\(firebaseProjectId)","sub":"\(uid)","iat":\(nowSeconds),"exp":\(nowSeconds + 3600),"v":\(version)}
        """
        let encodedHeader = base64URLEncode(header)
        let encodedPayload = base64URLEncode(payload)
        // Unsigned: the signature segment is intentionally empty (001 §2.3's "unsigned tokens").
        return "\(encodedHeader).\(encodedPayload)."
    }

    private static func base64URLEncode(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
