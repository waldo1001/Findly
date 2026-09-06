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
    ///
    /// **specs/009 §5.1 "iOS execution model" (amended 2026-09-06, I51 review, finding 2 — Major).**
    /// A `LOCATE_REQUEST`'s capture can legitimately run close to the full ~30 s the OS allows this
    /// callback before penalising the app for overrunning it, and `dispatcher.dispatch` awaits the
    /// capture *and* the fulfil network round trip. I51's first pass completed the handler at t≈0
    /// (immediately after starting the dispatch), reasoning that was "safe and conservative" — it is
    /// not: `beginBackgroundTask` on modern iOS reports roughly the same ~30 s remaining-time figure
    /// as the push window itself, so finishing this handler early buys essentially no extra
    /// wall-clock — it trades a guaranteed window for a best-effort one — and `beginBackgroundTask`
    /// can return `.invalid` (Background App Refresh disabled), in which case completing with no
    /// assertion at all risks the process being suspended mid-capture, a path where the previous
    /// await-then-complete behaviour would have kept it alive.
    ///
    /// Fixed by bounding the wait instead of abandoning it: the capture starts immediately (inside
    /// the OS push window, never delayed by the assertion), then this method races that dispatch
    /// against a deadline comfortably inside the OS budget (~25 s), completing the handler on
    /// whichever wins — never later than "as soon as sent", which is the MUST's actual requirement,
    /// since `LocateRequestPushHandler.handle` awaits its fulfil POST, so "dispatch returned" is at
    /// or after "fulfil sent". Either way, the still-live assertion keeps the process alive while
    /// this method continues awaiting the dispatch to actually finish before ending the background
    /// task — covering the tail past this handler's own return, exactly what `beginBackgroundTask`
    /// is for. When no assertion was granted at all (`.invalid`), there is no tail-covering
    /// mechanism whatsoever, so this falls back to awaiting the dispatch before completing — the
    /// pre-I51 behaviour this path reduces to. This method stays deliberately thin/untested glue
    /// (repo convention): the testable behaviour lives in `LocateRequestPushHandler`.
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

        // Start the capture inside the OS push window immediately — the assertion below only
        // extends the TAIL past this handler's own return, it must never delay the start.
        let dispatchTask = Task { await dispatcher.dispatch(data) }

        let backgroundTask = BackgroundTaskEnder(application: application)
        guard backgroundTask.begin(name: "com.findly.push.dispatch") else {
            // `.invalid` — no assertion at all (Background App Refresh disabled). The only thing
            // that can keep the process alive now is this handler staying outstanding, so fall back
            // to awaiting the dispatch (capture + `handle`'s awaited fulfil POST) before completing.
            Task {
                await dispatchTask.value
                completionHandler(.newData)
            }
            return
        }

        Task {
            await PushCompletionRace.wait(for: dispatchTask, timeoutSeconds: 25)
            completionHandler(.newData)
            // Whichever won the race, keep the still-live assertion until the dispatch actually
            // finishes before ending it — the tail `beginBackgroundTask` exists to cover.
            await dispatchTask.value
            backgroundTask.end()
        }
    }
}

/// Races an already-started task against a fixed deadline, returning as soon as either finishes —
/// never waiting for the loser (used by `didReceiveRemoteNotification`, finding 2: the loser, if
/// it's the dispatch, keeps running afterward regardless and is awaited separately under the
/// background assertion). Pure timing glue, deliberately untested (repo convention) — nothing here
/// is a decidable business rule, only "don't block past whichever comes first."
private enum PushCompletionRace {
    static func wait(for task: Task<Void, Never>, timeoutSeconds: UInt64) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = ResumeOnce(continuation)
            Task {
                await task.value
                box.resume()
            }
            Task {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                box.resume()
            }
        }
    }

    /// Guards against the continuation being resumed twice (whichever of the two races above loses
    /// still calls `resume()` once it eventually completes/wakes).
    private final class ResumeOnce: @unchecked Sendable {
        private let continuation: CheckedContinuation<Void, Never>
        private let lock = NSLock()
        private var resumed = false

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            continuation.resume()
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// specs/001-api-contract.md §8.2 — without this, iOS does not banner a notification while the
    /// app is in the foreground; `GeofenceEventNotifying`'s locally-built request needs this to
    /// actually surface as a user-visible alert in that state.
    ///
    /// **specs/009-device-runtime.md §5.1 (amended 2026-09-06, I51 review, finding 3 — a spec
    /// reversal).** I51's first pass suppressed this for `LOCATE_REQUEST` (`willPresent` returning
    /// `[]`) per the section's then-current text. That text was wrong and has been fixed
    /// (`specs: 009 §5.1 — the locate alert is presented in the foreground too`): suppressing the
    /// alert when the app is foregrounded contradicted the same section's opening MUST that the
    /// located person *always* sees it, and reproduced on iOS the silent locate that section
    /// condemns on Android, in the exact window where the person is actually holding the phone —
    /// Android posts its notification regardless of app state, so the carve-out also broke parity.
    /// `willPresent` now returns `[.banner, .sound]` unconditionally, for every push type, matching
    /// pre-I51 behaviour. With no locate-specific branch left, there is no decidable rule here to
    /// extract into a `FindlyKit` type — this stays plain UIKit glue.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Thread-safe begin/end-once wrapper around `UIApplication`'s background-task API (specs/009 §5.1:
/// "wrap the work in `beginBackgroundTask` so the fulfil call can complete"). Pure UIKit glue,
/// deliberately untested (repo convention: `AppDelegate`/CoreLocation glue is thin and untested;
/// nothing here is a decidable rule — `LocateRequestPushHandler`'s capture/fulfil logic already
/// carries the testable behaviour). Guards against ending twice (both the normal completion path and
/// the OS expiration handler call `end()`; only the first has any effect).
private final class BackgroundTaskEnder {
    private let application: UIApplication
    private let lock = NSLock()
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(application: UIApplication) {
        self.application = application
    }

    /// Returns whether the OS actually granted an assertion — `false` (`.invalid`) happens when
    /// Background App Refresh is disabled, at which point there is no assertion covering anything
    /// and the caller must fall back to a different life-extension strategy (I51 review, finding 2).
    @discardableResult
    func begin(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        identifier = application.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
        return identifier != .invalid
    }

    func end() {
        lock.lock()
        let id = identifier
        identifier = .invalid
        lock.unlock()
        guard id != .invalid else { return }
        application.endBackgroundTask(id)
    }
}
