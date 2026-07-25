import Foundation

/// specs/004-ios-client.md §4, specs/006-phone-auth.md — phone-number-only sign-in abstraction.
/// `StubAuthProvider` is the dev/test implementation; `FirebaseAuthProvider` (app target,
/// `Findly/`) is the real implementation, swapped in at the `RootView` composition-root seam
/// (`AuthMode == .firebase`, specs/004 §8).
public protocol AuthProviding: AnyObject {
    var currentUserId: String? { get }
    func currentIDToken() async throws -> String
    /// specs/001 §2.1 — clients MUST refresh via the auth SDK and retry once on
    /// `AUTH_TOKEN_EXPIRED` (see `URLSessionAPIClient`).
    func refreshIDToken() async throws -> String
    func signOut() throws
    /// Starts SMS verification for the (already 006 §3-normalized) number. Re-calling with the
    /// same number = resend. The verification session (verificationId, resend token) is
    /// provider-internal and MUST NOT cross this interface. Throws `PhoneAuthError`.
    func startPhoneVerification(phoneNumberE164: String) async throws
    /// Confirms the code for the in-flight verification; on success `currentUserId != nil`.
    /// Throws `PhoneAuthError`.
    func confirmCode(_ code: String) async throws
    /// specs/008-privacy-endpoints.md §1.3 — deletes the Firebase Auth user client-side, called
    /// ONLY after `DELETE /users/me` (specs/001 §13.2) returns `204` — never before (an orphaned
    /// Firebase user with no Findly data is harmless; the reverse orphan would be an erasure
    /// failure). May throw if the SDK requires a recent sign-in; callers (`DeleteAccountViewModel`)
    /// surface a retry path rather than treating this as fatal.
    func deleteCurrentUser() async throws
}

public enum AuthError: Error, Equatable {
    case notSignedIn
}

/// specs/006-phone-auth.md §4.2 — the closed client-side error set both platforms map Firebase SDK
/// failures onto. Raw SDK text never reaches a screen; see `PhoneAuthError.userMessage`.
public enum PhoneAuthError: Error, Equatable, CaseIterable {
    case invalidPhoneNumber
    case tooManyRequests
    case smsQuotaExceeded
    case appVerificationFailed
    case invalidCode
    case codeExpired
    case network
    case unknown
}
