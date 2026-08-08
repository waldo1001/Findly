import FindlyKit
import Foundation
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// specs/009-device-runtime.md §5.5, specs/001-api-contract.md §4.1 — the real, on-device
/// `PushTokenProviding` (`FindlyKit`'s doc: "the real implementation bridges FCM/APNs delegate
/// callbacks into this stream"). Lives in the app target, not `FindlyKit` (mirrors
/// `FirebaseAuthProvider`'s precedent exactly), so `FindlyKit` stays Firebase-SDK-free and
/// `swift test` keeps running headless (specs/004 §9).
///
/// Bridges the raw APNs device token (delivered to `AppDelegate.application(_:
/// didRegisterForRemoteNotificationsWithDeviceToken:)`) into `Messaging.messaging().apnsToken`,
/// then surfaces the resulting **FCM token** (not the raw APNs token) via `MessagingDelegate` — the
/// FCM token is what `RegisterDeviceRequest.pushToken` expects (001 §4.1), matching Android's
/// `RealPushTokenProvider`/`FindlyMessagingService` model exactly: both platforms send the same
/// kind of token to the backend.
///
/// A singleton (`shared`) so `AppDelegate` (constructed by `@UIApplicationDelegateAdaptor`, whose
/// exact timing relative to `FindlyApp.init()` isn't something app code controls) and
/// `FindlyApp.init()` (which hands this to `DeviceRegistrationService.observePushTokenRefreshes`)
/// always reference the exact same instance regardless of which happens to run first.
///
/// **Ordering safety (deliberate design, not an accident):** `init()` below touches NOTHING
/// Firebase-SDK-side — it only sets up the `AsyncStream`. `Messaging.messaging()` is a hard
/// precondition failure if called before `FirebaseApp.configure()` has run, so the one call that
/// touches it (`startObservingMessaging()`) is a separate method, called explicitly from
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` strictly AFTER
/// `FirebaseApp.configure()` — never from `init()`/`shared`'s lazy first access, which could
/// plausibly happen before that (e.g. if `FindlyApp.init()`'s object graph is built before
/// `@UIApplicationDelegateAdaptor` invokes its delegate's launch callback).
final class FirebasePushTokenProvider: NSObject, PushTokenProviding {
    static let shared = FirebasePushTokenProvider()

    let tokenUpdates: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    private override init() {
        var continuation: AsyncStream<String>.Continuation!
        self.tokenUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
        super.init()
    }

#if canImport(FirebaseMessaging)
    /// Call once, from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, strictly AFTER
    /// `FirebaseApp.configure()`.
    func startObservingMessaging() {
        Messaging.messaging().delegate = self
    }

    /// Call from `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` —
    /// the APNs handshake's result feeds Messaging, which is what actually produces the FCM token
    /// surfaced through `tokenUpdates` below.
    func setAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// I32 (specs/004 §4.1) — call from `AppDelegate.didReceiveRemoteNotification`, for any payload
    /// `FirebaseAuthProvider.canHandleNotification` did not claim. With Firebase method swizzling
    /// disabled (`FirebaseAppDelegateProxyEnabled = NO`), `Messaging` no longer auto-observes
    /// notification delivery through its own swizzled interceptor, so its delivery-analytics/
    /// message-info bookkeeping needs this explicit forward to keep running — this app target
    /// doesn't consume the returned `MessagingMessageInfo` itself, so the result is discarded.
    func appDidReceiveMessage(_ userInfo: [AnyHashable: Any]) {
        _ = Messaging.messaging().appDidReceiveMessage(userInfo)
    }
#else
    // Firebase SDK not linked (shouldn't happen once project.yml's FirebaseMessaging dependency is
    // wired, but keeps this file buildable in isolation the same way FirebaseAuthProvider does).
    func startObservingMessaging() {}
    func setAPNSToken(_ deviceToken: Data) {}
    func appDidReceiveMessage(_ userInfo: [AnyHashable: Any]) {}
#endif
}

#if canImport(FirebaseMessaging)
extension FirebasePushTokenProvider: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // docs/security-review-checklist.md: never log the token itself - counts/error categories
        // only. Nothing is logged here at all, deliberately.
        guard let fcmToken else { return }
        continuation.yield(fcmToken)
    }
}
#endif
