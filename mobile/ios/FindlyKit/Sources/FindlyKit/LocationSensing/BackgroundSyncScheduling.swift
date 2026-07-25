import Foundation
#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// specs/004-ios-client.md §7 — opportunistic `BGAppRefreshTask` scheduling, behind a protocol so
/// callers stay testable without `BackgroundTasks`. Note: the `BackgroundTasks` *module* imports
/// fine on macOS too, but `BGTaskScheduler` itself is `API_UNAVAILABLE(macos)` — hence gating on
/// `os(iOS)` as well, not `canImport(BackgroundTasks)` alone (a real gap this session found by
/// trying to build for macOS, exactly the kind of platform mistake this gating rule exists to
/// catch).
public protocol BackgroundSyncScheduling {
    func scheduleNextSync()
    func cancelScheduledSync()
}

/// Test/macOS-build default.
public final class NoOpBackgroundSyncScheduler: BackgroundSyncScheduling {
    public init() {}
    public func scheduleNextSync() {}
    public func cancelScheduledSync() {}
}

#if os(iOS) && canImport(BackgroundTasks)
/// The real on-device implementation — scaffolded, not yet registered with `BGTaskScheduler`.
public final class SystemBackgroundSyncScheduler: BackgroundSyncScheduling {
    private let taskIdentifier: String

    public init(taskIdentifier: String = "com.findly.sync") {
        self.taskIdentifier = taskIdentifier
    }

    public func scheduleNextSync() {
        // TODO(on-device session): BGTaskScheduler.shared.submit(BGAppRefreshTaskRequest(...)),
        // and register the handler in the app target's App init via
        // BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:) — the
        // interval is a *target* only (000 §O2); iOS schedules opportunistically.
    }

    public func cancelScheduledSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }
}
#endif
