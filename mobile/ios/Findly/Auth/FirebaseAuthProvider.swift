import Foundation
import FindlyKit
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
// `FirebaseApp` (configuration + the already-configured check) lives in FirebaseCore, not
// FirebaseAuth — see `configureFirebaseIfNeeded()`.
import FirebaseCore
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
    }

    /// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §1.3 (review finding #5) —
    /// removes the Keychain-backed phone-verification session id as its OWN unconditional step,
    /// deliberately NOT nested inside `signOut()`: `signOut()` can throw (e.g. `Auth.auth().signOut()`
    /// failing) and callers invoke it via `try?` (`DeleteAccountViewModel`), so a clear nested after
    /// the throwing call could be skipped entirely and strand the entry. MUST NOT throw —
    /// `KeychainStoring.removeString` already swallows its own storage errors, and callers reach
    /// this during an already-in-progress irreversible account wipe / sign-out-for-retry where
    /// there is no meaningful failure recovery left to offer.
    func clearStoredSession() {
        verificationID = nil
    }

    /// specs/008-privacy-endpoints.md §1.3 — called by `DeleteAccountViewModel` ONLY after
    /// `DELETE /users/me` returns `204`. May throw `requiresRecentLogin` if the SDK demands a
    /// fresh sign-in for this sensitive operation; the ViewModel surfaces the sign-out-then-retry
    /// recovery (§1.3) rather than treating that as fatal. Deliberately does NOT also call
    /// `signOut()`/`clearStoredSession()` — the ViewModel does that itself, uniformly, once the
    /// whole flow (this call + the local-state wipe, or the sign-out-for-retry path) completes.
    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.notSignedIn }
        try await user.delete()
    }

    /// Firebase phone auth needs to prove the request came from *this* app before it will send an
    /// SMS. On iOS it does that with a silent APNs push, falling back to a reCAPTCHA web view.
    /// Neither was wired up, which is why sign-in crashed on device the moment `FirebaseAuth` was
    /// actually linked (2026-08-05): `Auth` never received an APNs token — the token was being
    /// handed to `Messaging` only, which is a *different* Firebase component — and the reCAPTCHA
    /// fallback is impossible here because `GoogleService-Info.plist` carries no
    /// `REVERSED_CLIENT_ID` (that key only exists when Google Sign-In is enabled, and this project
    /// is phone-auth-only, specs/006 §1). With no verification path available and
    /// `uiDelegate: nil`, `verifyPhoneNumber` had nowhere to go.
    ///
    /// **I32 (2026-08-08):** fixing the above by linking `FirebaseAuth` was not enough — Auth's
    /// notification-forwarding self-check never reached `AppDelegate.didReceiveRemoteNotification`
    /// because Firebase's method swizzling is incompatible with SwiftUI's
    /// `UIApplicationDelegateAdaptor` here, so `verifyPhoneNumber` failed instantly with
    /// `FIRAuthErrorDomain 17054 ERROR_NOTIFICATION_NOT_FORWARDED` in every Release/TestFlight
    /// build (Debug hid it via `configureForCurrentBuild()`'s `isAppVerificationDisabledForTesting`,
    /// and the Simulator has no APNs to expose it either way). Fixed by disabling swizzling
    /// (`FirebaseAppDelegateProxyEnabled = NO`, `Info.plist`) and forwarding every callback it used
    /// to intercept manually — this method is now called for real; see `apnsTokenGate` below for
    /// why it is still not a bare, unguarded `Auth.setAPNSToken` call.
    ///
    /// Call from `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`,
    /// alongside the Messaging equivalent. `.unknown` lets Firebase detect sandbox vs production
    /// itself, which matters because debug builds use the APNs sandbox and TestFlight/App Store
    /// builds use production, against the same uploaded `.p8` key.
    ///
    /// **Still must not call `Auth.setAPNSToken` unguarded from this raw callback** — see
    /// `AppDelegate`'s `didRegisterForRemoteNotificationsWithDeviceToken` for the full account of
    /// the `c725a41` trap this guards against. With swizzling now OFF, nothing else forwards the
    /// token to Auth at all, so the guard can no longer just defer to Firebase's own (now-disabled)
    /// interceptor — `apnsTokenGate` is that guard: it stashes the token until
    /// `markAuthReadyForAPNSToken()` confirms Auth is safe to touch.
    private static let apnsTokenGate = PendingAPNSTokenGate()

    static func setAPNSToken(_ deviceToken: Data) {
        apnsTokenGate.offer(deviceToken) { Auth.auth().setAPNSToken($0, type: .unknown) }
    }

    /// Marks Auth as safe to receive the APNs token directly and flushes anything `setAPNSToken`
    /// stashed before this ran. Called defensively from the top of `startPhoneVerification` —by
    /// the time a user reaches "send code" the app has been running long enough that the launch-
    /// time race `apnsTokenGate` guards against (Auth's async `protectedDataInitialization()` not
    /// having assigned `tokenManager` yet) cannot still be in flight, so this is a safe point
    /// regardless of how early or late the APNs callback itself fired.
    private static func markAuthReadyForAPNSToken() {
        apnsTokenGate.markReady { Auth.auth().setAPNSToken($0, type: .unknown) }
    }

    /// Call FIRST from `AppDelegate.application(_:didReceiveRemoteNotification:...)`. Firebase's
    /// app-verification push is addressed to the app like any other silent push; if it isn't
    /// handed to `Auth`, verification never completes and the app would also try to dispatch it as
    /// if it were one of specs/001 §8's own push types.
    static func canHandleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        Auth.auth().canHandleNotification(userInfo)
    }

    /// Call from `FindlyApp`'s `.onOpenURL`, BEFORE `AppCoordinator.handleDeepLink`. specs/004
    /// §4.1's reCAPTCHA web-sheet fallback (used when APNs verification isn't available — the
    /// Simulator, or a device before the silent push completes) returns control to the app via the
    /// `app-1-…` `REVERSED_CLIENT_ID` custom scheme already declared in `Info.plist`; `Auth` claims
    /// that URL and resumes verification itself. Any URL Auth doesn't recognize — the app's own
    /// `findly://`/`https://{joinLinkHost}` deep links — falls through unclaimed to the coordinator.
    static func canHandle(_ url: URL) -> Bool {
        Auth.auth().canHandle(url)
    }

    /// Configures the default `FirebaseApp` if it isn't configured yet, and is safe to call more
    /// than once (a second bare `FirebaseApp.configure()` logs a duplicate-app error).
    ///
    /// Why this exists rather than a single `configure()` in the app delegate: SwiftUI runs
    /// `App.init()` **before** `application(_:didFinishLaunchingWithOptions:)`, and specs/004 §2.6
    /// requires `FindlyApp.init()` to read the restored `Auth.auth().currentUser` to pick the
    /// launch route. Touching `Auth` before configuration is a hard crash, so the earliest caller
    /// configures and the delegate's later call becomes a no-op. Ordering between the two is
    /// therefore no longer load-bearing.
    static func configureFirebaseIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    /// True when a previous session's user was restored from the keychain — specs/004 §2.6's
    /// launch-route input. MUST be called after `configureFirebaseIfNeeded()`.
    static var hasRestoredSession: Bool {
        Auth.auth().currentUser != nil
    }

    /// Call once, from `didFinishLaunchingWithOptions`, strictly AFTER `FirebaseApp.configure()`.
    ///
    /// In DEBUG only, disables Firebase's app verification. The Simulator has no APNs at all, so
    /// without this the phone-auth flow cannot be exercised locally and every change has to be
    /// round-tripped through a TestFlight build — which is exactly how this bug survived three
    /// uploads. With verification disabled, the console-configured test numbers
    /// (`+32 470 00 00 01` / `123456`, specs/006 §5) sign in on the Simulator.
    ///
    /// Guarded by `#if DEBUG` so it can never reach a Release build: switching it on in
    /// production would disable the anti-abuse check that stops anyone burning SMS quota, which
    /// is precisely what specs/006 §6.3's App Check ordering exists to protect.
    static func configureForCurrentBuild() {
        #if DEBUG
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        #endif
    }

    func startPhoneVerification(phoneNumberE164: String) async throws {
        // I32 — defensive flush of any APNs token stashed by an early `setAPNSToken` callback; see
        // that method's doc and `apnsTokenGate` for why this is the safe point to apply it.
        Self.markAuthReadyForAPNSToken()
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
    func clearStoredSession() {}
    func deleteCurrentUser() async throws { throw AuthError.notSignedIn }
    func startPhoneVerification(phoneNumberE164: String) async throws { throw PhoneAuthError.unknown }
    func confirmCode(_ code: String) async throws { throw PhoneAuthError.unknown }
    static func setAPNSToken(_ deviceToken: Data) {}
    static func canHandleNotification(_ userInfo: [AnyHashable: Any]) -> Bool { false }
    static func canHandle(_ url: URL) -> Bool { false }
    static func configureForCurrentBuild() {}
    static func configureFirebaseIfNeeded() {}
    /// No SDK linked means no persisted session to restore — the app starts at sign-in, which is
    /// the correct answer for this build shape (specs/004 §2.6).
    static var hasRestoredSession: Bool { false }
#endif
}
