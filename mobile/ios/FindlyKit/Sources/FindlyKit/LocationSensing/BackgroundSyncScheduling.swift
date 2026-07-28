import Foundation
#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// specs/009-device-runtime.md §3.4 — opportunistic `BGAppRefreshTask` scheduling, behind a
/// protocol so callers stay testable without `BackgroundTasks`. Note: the `BackgroundTasks`
/// *module* imports fine on macOS too, but `BGTaskScheduler` itself is `API_UNAVAILABLE(macos)` —
/// hence gating on `os(iOS)` as well, not `canImport(BackgroundTasks)` alone.
public protocol BackgroundSyncScheduling {
    /// Submits (or re-submits) the next opportunistic `BGAppRefreshTask` request. `afterDelay`
    /// lets a caller applying `BackoffPolicy` push the earliest-begin-date out after a transient
    /// failure (specs/009 §9); `nil` submits with no explicit `earliestBeginDate` (the system
    /// decides, per §3.4 — "the system decides actual frequency").
    func scheduleNextSync(afterDelay: TimeInterval?)
    func cancelScheduledSync()
}

extension BackgroundSyncScheduling {
    public func scheduleNextSync() { scheduleNextSync(afterDelay: nil) }
}

/// Test/macOS-build default.
public final class NoOpBackgroundSyncScheduler: BackgroundSyncScheduling {
    public init() {}
    public func scheduleNextSync(afterDelay: TimeInterval?) {}
    public func cancelScheduledSync() {}
}

#if os(iOS) && canImport(BackgroundTasks)
/// The real on-device implementation. specs/009 §3.4's identifier is `be.dynex.findly.refresh`.
///
/// **Registration is a two-step dance split across process lifetime**, per Apple's own
/// requirement that `BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)` MUST
/// run before `App.init`/`application(_:didFinishLaunchingWithOptions:)` returns — long before any
/// dependency graph (API client, auth, the fix queue) exists. `registerLaunchHandler` is therefore
/// a **static** method the app target calls first thing in `FindlyApp.init()`, taking a closure
/// that is itself resolved lazily (see `LocationRuntimeContainer`'s doc for how the app target
/// bridges "register early" with "the work needs a fully-constructed object graph that only exists
/// once `RootView` runs"). `scheduleNextSync`/`cancelScheduledSync` (instance methods, used by
/// `LocationRuntimeContainer` after construction) are what actually submit/cancel a request —
/// unrelated to registration and callable any time after `register` has run once per process.
public final class SystemBackgroundSyncScheduler: BackgroundSyncScheduling {
    /// specs/009-device-runtime.md §3.4's normative identifier — MUST also appear in
    /// `Findly/Info.plist`'s `BGTaskSchedulerPermittedIdentifiers` array (a `submit()` for an
    /// identifier missing from that array throws `BGTaskSchedulerError.notPermitted`).
    public static let taskIdentifier = "be.dynex.findly.refresh"

    private let taskIdentifier: String

    public init(taskIdentifier: String = SystemBackgroundSyncScheduler.taskIdentifier) {
        self.taskIdentifier = taskIdentifier
    }

    public func scheduleNextSync(afterDelay: TimeInterval?) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        if let afterDelay {
            request.earliestBeginDate = Date(timeIntervalSinceNow: afterDelay)
        }
        // specs/009 §9: never log coordinates/deviceId/tokens - a submission failure (e.g. too
        // many pending requests, simulator quirks) is swallowed here; worst case the next natural
        // trigger (significant-location-change or foreground) still drives a capture.
        try? BGTaskScheduler.shared.submit(request)
    }

    public func cancelScheduledSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    /// MUST be called before `App.init`/`didFinishLaunchingWithOptions` returns (Apple's own
    /// requirement) — `FindlyApp.init()` is this call's one production call site. `handler` is
    /// invoked on every system-driven launch of the task; it MUST call `scheduleNextSync` again
    /// before returning (specs/009 §3.4: "rescheduled at the end of every run") — that
    /// responsibility lives in whatever `handler` closure the caller supplies (see
    /// `LocationRuntimeContainer.handleBackgroundRefresh`), not here, since this method has no
    /// access to a `LocationSyncRunner`/`BackoffPolicy` at registration time.
    public static func registerLaunchHandler(identifier: String = SystemBackgroundSyncScheduler.taskIdentifier, handler: @escaping () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task {
                await handler()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                work.cancel()
            }
        }
    }
}
#endif
