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
    /// surface the 008 §1.3 sign-out-then-retry recovery rather than treating this as fatal (a
    /// bare retry is a trap — `requires-recent-login` never clears on its own).
    func deleteCurrentUser() async throws
    /// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §1.3 — removes any
    /// locally-stored session material (the Keychain-backed phone-verification session id, I7) as
    /// its OWN unconditional step. Deliberately NOT a side effect of `signOut()`'s internal
    /// ordering: `signOut()` can throw (e.g. on Keychain-access failure) and, if the clear were
    /// nested inside it, leave the entry behind. MUST NOT throw — implementations swallow their
    /// own storage errors, since callers invoke this during an already-in-progress irreversible
    /// account wipe where there is no meaningful failure recovery left to offer.
    func clearStoredSession()
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
    case regionNotAllowed
    case appVerificationFailed
    case invalidCode
    case codeExpired
    case network
    case unknown
}
