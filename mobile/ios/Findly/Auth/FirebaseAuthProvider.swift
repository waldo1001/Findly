import Foundation
import FindlyKit
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// specs/004-ios-client.md §4.1 — the first real `AuthProviding` implementation. Lives in the app
/// target (not `FindlyKit`) so `FindlyKit` stays Firebase-SDK-free and `swift test` keeps running
/// headless on macOS (specs/004 §9). Swapped in at the `RootView` composition-root seam when
/// `AppConfig.authMode == .firebase` (specs/004 §8) — that seam is wired in this same change.
///
/// **H1/H2 status (docs/implementation-handoff.md):** no Firebase SDK dependency and no
/// `GoogleService-Info.plist` exist in the app target yet, and no `.xcodeproj` exists yet either
/// (specs/004 §1.1) — so the `#if canImport(FirebaseAuth)` branch below is unreachable in any
/// build this session can run; it compiles to the inert `#else` fallback. This is intentional and
/// matches the task's known posture: on-device real Firebase phone verification depends on H2
/// (Firebase console phone-auth setup, `docs/azure-setup.md` §3) and is expected to stay
/// stubbed/untestable locally until H1 (SDK + plist + Xcode project) and H2 both land — at which
/// point the exact `FirebaseAuth` API shapes below should be re-verified against the real SDK
/// (this session has no linked SDK to check them against).
final class FirebaseAuthProvider: AuthProviding {
#if canImport(FirebaseAuth)
    private static let verificationIDKeychainKey = "com.findly.phoneAuth.verificationID"

    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
    }

    // Stored in the Keychain (I7 hardening — previously UserDefaults, flagged non-blocking in I3's
    // security review): the app may be backgrounded while the SMS arrives, so the verification
    // session must survive a relaunch, but it's a Firebase session handle, not something that
    // belongs in plaintext, unencrypted storage. See KeychainStore's doc comment for the
    // accessibility-class rationale.
    private var verificationID: String? {
        get { keychain.string(forKey: Self.verificationIDKeychainKey) }
        set {
            if let newValue {
                keychain.setString(newValue, forKey: Self.verificationIDKeychainKey)
            } else {
                keychain.removeString(forKey: Self.verificationIDKeychainKey)
            }
        }
    }

    var currentUserId: String? { Auth.auth().currentUser?.uid }

    func currentIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        return try await user.getIDToken()
    }

    func refreshIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        return try await user.getIDToken(forcingRefresh: true)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        verificationID = nil
    }

    /// specs/008-privacy-endpoints.md §1.3 — called by `DeleteAccountViewModel` ONLY after
    /// `DELETE /users/me` returns `204`. May throw `requiresRecentLogin` if the SDK demands a
    /// fresh sign-in for this sensitive operation; the ViewModel surfaces a retry path rather than
    /// treating that as fatal (§1.3: "Clients MUST surface a retry path when the Firebase step
    /// fails"). Deliberately does NOT also call `signOut()`/clear the Keychain — the ViewModel does
    /// that itself, uniformly, once the whole flow (this call + the local-state wipe) completes.
    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        try await user.delete()
    }

    func startPhoneVerification(phoneNumberE164: String) async throws {
        do {
            verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumberE164, uiDelegate: nil)
        } catch {
            throw Self.mapError(error)
        }
    }

    func confirmCode(_ code: String) async throws {
        guard let verificationID else {
            // No verification in flight (e.g. app relaunched mid-flow and the Keychain entry was
            // cleared) — reads as CODE_EXPIRED ("must request a new code"), matching Android's
            // already-merged FirebaseAuthProvider/DevAuthProvider (specs/006 §4.2/§5).
            throw PhoneAuthError.codeExpired
        }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
        do {
            _ = try await Auth.auth().signIn(with: credential)
            self.verificationID = nil
        } catch {
            throw Self.mapError(error)
        }
    }

    /// specs/006-phone-auth.md §4.2 — raw SDK text never reaches a screen; map every Firebase Auth
    /// SDK failure onto the closed `PhoneAuthError` set by its `AuthErrorCode`.
    private static func mapError(_ error: Error) -> PhoneAuthError {
        let nsError = error as NSError
        switch AuthErrorCode(rawValue: nsError.code) {
        case .invalidPhoneNumber, .missingPhoneNumber:
            return .invalidPhoneNumber
        case .tooManyRequests:
            return .tooManyRequests
        case .quotaExceeded:
            return .smsQuotaExceeded
        case .appNotVerified, .appNotAuthorized, .missingAppCredential, .invalidAppCredential, .webContextCancelled, .webInternalError:
            return .appVerificationFailed
        case .invalidVerificationCode, .missingVerificationCode:
            return .invalidCode
        case .sessionExpired, .invalidVerificationID, .missingVerificationID:
            return .codeExpired
        case .networkError:
            return .network
        default:
            return .unknown
        }
    }
#else
    // Firebase SDK not linked yet (H1 follow-up) — an inert fallback so RootView can reference
    // this type unconditionally once an Xcode project + the Firebase SPM dependency exist, even
    // before GoogleService-Info.plist is wired in.
    var currentUserId: String? { nil }
    func currentIDToken() async throws -> String { throw AuthError.notSignedIn }
    func refreshIDToken() async throws -> String { throw AuthError.notSignedIn }
    func signOut() throws {}
    func deleteCurrentUser() async throws { throw AuthError.notSignedIn }
    func startPhoneVerification(phoneNumberE164: String) async throws { throw PhoneAuthError.unknown }
    func confirmCode(_ code: String) async throws { throw PhoneAuthError.unknown }
#endif
}
