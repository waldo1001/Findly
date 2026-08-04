import FindlyKit
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif

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
#if canImport(FirebaseCore)
        // MUST run before anything touches `Messaging.messaging()` (a hard precondition failure
        // otherwise) - see `FirebasePushTokenProvider`'s doc for why `startObservingMessaging()` is
        // a separate, explicitly-ordered call rather than something `init()`/`shared`'s lazy first
        // access could trigger too early.
        FirebaseApp.configure()
#endif
        FirebasePushTokenProvider.shared.startObservingMessaging()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
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
