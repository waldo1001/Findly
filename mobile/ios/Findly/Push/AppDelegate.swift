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
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        FirebasePushTokenProvider.shared.setAPNSToken(deviceToken)
        // Deliberately NOT forwarded to FirebaseAuth here. `c725a41` added
        // `FirebaseAuthProvider.setAPNSToken(deviceToken)` on the reasoning that Auth is a separate
        // component needing its own copy of the token. True in principle, but it crashed the app on
        // launch:
        //
        //   FirebaseAuth/Auth.swift:1592: Fatal error: Unexpectedly found nil while implicitly
        //   unwrapping an Optional value
        //
        // `Auth.setAPNSToken` writes `self.tokenManager.token`, and `tokenManager` is an
        // implicitly-unwrapped optional assigned only inside `Auth.protectedDataInitialization()`.
        // That runs asynchronously (and can be deferred to
        // `protectedDataDidBecomeAvailableNotification`), so an APNs callback arriving first hits
        // nil and traps.
        //
        // Firebase's OWN path does not have this problem: it registers its app-delegate interceptor
        // via `GULAppDelegateSwizzler.registerAppDelegateInterceptor(self)` *inside* that same
        // initialization, i.e. strictly after `tokenManager` exists — so it cannot fire too early.
        // Swizzling is enabled (this target sets no `FirebaseAppDelegateProxyEnabled` key), so Auth
        // already receives the token by itself. Forwarding manually is redundant AND unguarded,
        // which is the entire bug. Only re-add this if swizzling is ever disabled, and then only
        // behind a readiness check.
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
