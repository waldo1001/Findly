import FindlyKit
import UIKit
import UserNotifications
// FirebaseCore is no longer imported here: configuration moved behind
// `FirebaseAuthProvider.configureFirebaseIfNeeded()` (specs/004 §2.6), so this file references no
// FirebaseCore type of its own.

/// specs/004-ios-client.md §1.1's explicit allowance ("passing the OS lifecycle... push-
/// registration callbacks... into FindlyKit types through their public protocols") — this class
/// is pure `UIApplicationDelegate` glue. Every line of actual push-routing LOGIC lives in
/// `FindlyKit` (`PushMessageDispatcher` and its four handlers, reached via
/// `PushRuntimeContainerHolder.shared.container`, populated once by `FindlyApp.init()`); this file
/// only forwards raw OS/Firebase callbacks into that seam.
///
/// Wired into `FindlyApp` via `@UIApplicationDelegateAdaptor(AppDelegate.self)`.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // MUST run before anything touches `Messaging.messaging()` (a hard precondition failure
        // otherwise) - see `FirebasePushTokenProvider`'s doc for why `startObservingMessaging()` is
        // a separate, explicitly-ordered call rather than something `init()`/`shared`'s lazy first
        // access could trigger too early.
        //
        // Idempotent as of specs/004 §2.6: `FindlyApp.init()` runs BEFORE this delegate callback
        // and needs Firebase configured to read the restored session for its launch route, so it
        // configures first and this call is normally a no-op. Kept here regardless so this
        // delegate never depends on who ran first.
        FirebaseAuthProvider.configureFirebaseIfNeeded()
        // Must follow FirebaseApp.configure(). DEBUG-only: disables app verification so the
        // phone-auth flow is exercisable on the Simulator, which has no APNs — see the method's
        // doc comment for why that matters.
        FirebaseAuthProvider.configureForCurrentBuild()
        FirebasePushTokenProvider.shared.startObservingMessaging()
        UNUserNotificationCenter.current().delegate = self
        // I33 — register for remote notifications UNCONDITIONALLY at launch. This obtains the APNs
        // device token WITHOUT prompting the user (user-facing alerts need UNUserNotificationCenter
        // authorization; a silent device token does not). Firebase phone-auth's app attestation
        // needs that token BEFORE `verifyPhoneNumber` runs: with a token, Auth uses the silent-push
        // credential path; without one it falls back to the notification-forwarding prober, which
        // is unreachable through SwiftUI's `UIApplicationDelegateAdaptor` proxy and fails every
        // sign-in with `FIRAuthErrorDomain 17054`. Previously this call was gated behind
        // `currentUserId != nil` in FindlyApp's onSignedIn closure — a chicken-and-egg deadlock: no
        // token until signed in, no sign-in without the token. Proven on-device 2026-08-08.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // I33 — Firebase method swizzling is ON (default), so Firebase's own interceptor forwards
        // this token to BOTH Messaging and Auth, and it does so crash-safely because that
        // interceptor is registered inside Auth's `protectedDataInitialization()` — strictly after
        // the `tokenManager` IUO exists. We deliberately do NOT call `Auth.setAPNSToken` ourselves:
        // I32 tried that (with swizzling off) and it trapped on device the instant the pending-token
        // gate flushed, because there is no point in our own code that is guaranteed to run after
        // that async init. Messaging's APNs token is likewise handled by the swizzler; this explicit
        // call is retained only as the FCM-token provider's documented feed and is trap-free
        // (`Messaging.apnsToken` is a plain settable property).
        FirebasePushTokenProvider.shared.setAPNSToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // docs/security-review-checklist.md: category only, never raw error text that could carry
        // device-identifying detail.
    }

    /// The universal remote-notification entry point (fires for both the data-only pushes -
    /// LOCATE_REQUEST/SETTINGS_CHANGED/GEOFENCE_CONFIG_CHANGED, all `content-available: 1` - and,
    /// while the app is foreground/backgrounded-but-running, the GEOFENCE_EVENT alert push too).
    /// specs/009-device-runtime.md §5 intro: `data.type` parsing/dispatch never crashes on a
    /// malformed payload - `PushMessageDispatcher.dispatch` already guarantees that, so this method
    /// has nothing further to guard.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Firebase's phone-auth verification push must be offered to Auth first: it looks like any
        // other silent push, and if Auth never sees it, verification stalls and we would also try
        // to dispatch it as though it were one of specs/001 §8's own types.
        // With swizzling ON (I33), Firebase's interceptor already had first look at this payload and
        // consumed its own phone-auth receipt/verification pushes before this method runs. This
        // remaining call is defensive for our own §8 types: if Auth still claims it, defer.
        if FirebaseAuthProvider.canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        guard let dispatcher = PushRuntimeContainerHolder.shared.container?.dispatcher else {
            completionHandler(.noData)
            return
        }
        // I15 round-2 code review: shared with FindlyNotificationService's NotificationService,
        // which needs the identical [AnyHashable: Any] -> [String: String] conversion — one
        // FindlyKit implementation instead of two independent copies of the same few lines.
        let data = PushPayloadParsing.stringData(from: userInfo)
        Task {
            await dispatcher.dispatch(data)
            completionHandler(.newData)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// specs/001-api-contract.md §8.2 — without this, iOS does not banner a notification while the
    /// app is in the foreground; `GeofenceEventNotifying`'s locally-built request needs this to
    /// actually surface as a user-visible alert in that state.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
