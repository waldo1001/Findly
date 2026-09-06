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
            // specs/009 §3.4 (I50 fix 2, amended 2026-09-06): "the registered handler MUST set an
            // expirationHandler that cancels the work AND calls setTaskCompleted(success: false)."
            // Apple's contract is that the expiration handler itself marks the task complete; a
            // task left uncompleted is terminated by the system and counted against the app's
            // future refresh budget. The shipped handler only cancelled `work`, never completing
            // it — combined with item 1's fix (every run burning its full 30 s while
            // `allowsBackgroundLocationUpdates` was false), this had been progressively starving
            // the app of background time.
            //
            // I50 review fix 4 (Major): `work.cancel()` is cooperative and `LocationSyncRunner.
            // runOnce()` awaits network I/O with no cancellation checks, so it typically finishes
            // AFTER the expiration handler above already completed the task — the two
            // `setTaskCompleted` calls below used to race unsynchronized. `BackgroundTaskCompletionGuard`
            // is the pure, unit-tested "first call wins" guard that makes whichever of the two
            // fires first win, and the other a no-op; `adapter` is the thin, `#if os(iOS) &&
            // canImport(BackgroundTasks)`-only glue that lets the guard operate on the real
            // `refreshTask`/`work` pair through `BackgroundTaskCompleting` without needing to know
            // about either concrete type.
            let completionGuard = BackgroundTaskCompletionGuard()
            let adapter = BGAppRefreshTaskCompletionAdapter(refreshTask: refreshTask)
            adapter.work = Task {
                await handler()
                completionGuard.complete(adapter, success: true)
            }
            refreshTask.expirationHandler = {
                completionGuard.expire(adapter)
            }
        }
    }
}

/// specs/009 §3.4 (I50 fix 4) — the one production conformance to `BackgroundTaskCompleting`,
/// adapting a real `BGAppRefreshTask` + its `Task<Void, Never>` work handle. `work` is a `var`,
/// set immediately after construction rather than passed to `init`, because the work `Task` itself
/// needs a reference to this adapter (to call `completionGuard.complete(adapter, ...)`) before it
/// can exist — see `registerLaunchHandler` above.
private final class BGAppRefreshTaskCompletionAdapter: BackgroundTaskCompleting {
    private let refreshTask: BGAppRefreshTask
    var work: Task<Void, Never>?

    init(refreshTask: BGAppRefreshTask) {
        self.refreshTask = refreshTask
    }

    func cancelWork() { work?.cancel() }
    func setTaskCompleted(success: Bool) { refreshTask.setTaskCompleted(success: success) }
}
#endif
