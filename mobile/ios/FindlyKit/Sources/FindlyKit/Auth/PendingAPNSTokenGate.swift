import Foundation

/// specs/004-ios-client.md §4.1, I32 — Firebase-SDK-free readiness gate for forwarding the raw
/// APNs device token to `Auth`. Kept in `FindlyKit` (not the app target) purely so its
/// readiness/pending semantics are unit-testable without a linked Firebase SDK; the app target's
/// `FirebaseAuthProvider` is the only caller and supplies the real `Auth.setAPNSToken(_:type:)`
/// call as `apply`.
///
/// Exists because disabling Firebase method swizzling (`FirebaseAppDelegateProxyEnabled = NO`,
/// I32) stops anything from auto-forwarding the APNs token to `Auth`, and forwarding it
/// unconditionally from the raw `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`
/// callback reopens the crash `c725a41` introduced: `Auth.setAPNSToken` writes
/// `self.tokenManager.token`, and `tokenManager` is an implicitly-unwrapped optional assigned only
/// inside `Auth`'s async `protectedDataInitialization()` — a callback arriving before that has run
/// hits nil and traps. This type never calls `apply` until told it is safe to, so a caller can wire
/// `offer(_:apply:)` straight to the raw callback with no crash risk regardless of ordering.
///
/// **Thread safety is type-enforced, not caller-enforced.** `offer` runs on the main thread (it's
/// wired to a UIKit `AppDelegate` callback) while `markReady` runs as the first statement of
/// `FirebaseAuthProvider.startPhoneVerification`, a `nonisolated async` function — such a function
/// hops OFF its `@MainActor` caller onto the global concurrent executor before its first statement
/// runs, so `markReady` genuinely executes concurrently with `offer`, not merely "later on the same
/// queue". `pendingToken`/`isReady` are therefore guarded by an internal `NSLock` covering every
/// read and write of both properties in both methods (including the `apply` call itself, so a
/// flush and a fresh `offer` can never interleave into a state where the token is silently lost or
/// double-applied). Callers get a plain synchronous API and never need to add their own
/// synchronization around this type.
public final class PendingAPNSTokenGate {
    public init() {}

    private let lock = NSLock()
    private var pendingToken: Data?
    private var isReady = false

    /// Call every time a fresh APNs token arrives (i.e. from the raw APNs callback). Applies
    /// immediately if `markReady` has already run this process; otherwise stashes the token,
    /// overwriting anything stashed earlier (only the latest token matters).
    public func offer(_ token: Data, apply: (Data) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard isReady else {
            pendingToken = token
            return
        }
        apply(token)
    }

    /// Call once from a point in app startup guaranteed to run after Auth's async initialization
    /// has completed — this codebase's call site is the top of `startPhoneVerification`, since by
    /// the time the user reaches "send code" the app has been running long enough that the launch
    /// race this guards against cannot still be in flight. Flushes a stashed token, if any, exactly
    /// once, then stays ready for the rest of the process so any later `offer` applies immediately.
    public func markReady(apply: (Data) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        isReady = true
        guard let token = pendingToken else { return }
        pendingToken = nil
        apply(token)
    }
}
