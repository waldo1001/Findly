import Foundation

/// specs/009-device-runtime.md §3.4 (I50 fix 4, Major) — the tiny seam `BackgroundTaskCompletionGuard`
/// needs from a real `BGAppRefreshTask` + its `Task<Void, Never>` work handle, so the guard's "first
/// call wins" property is testable without `BackgroundTasks` (`#if os(iOS) &&
/// canImport(BackgroundTasks)`, platform glue `swift test` cannot exercise on macOS).
public protocol BackgroundTaskCompleting: AnyObject {
    /// The cooperative cancel — `Task.cancel()` in production. Cooperative means this alone does
    /// NOT guarantee the work stops before `setTaskCompleted` is called; `LocationSyncRunner.
    /// runOnce()` awaits network I/O with no cancellation checks, so it typically keeps running
    /// after this and tries to complete on its own too, which is exactly the race
    /// `BackgroundTaskCompletionGuard` closes.
    func cancelWork()
    func setTaskCompleted(success: Bool)
}

/// Ensures `setTaskCompleted` is called AT MOST ONCE across both of a `BGAppRefreshTask`'s two
/// completion-relevant call sites — its own work finishing normally, and Apple's expiration
/// handler firing first. Completing a `BGTask` twice is API misuse whose failure mode is exactly
/// the background-budget starvation this fix exists to stop (the shipped handler only ever
/// cancelled the work on expiration, never completed the task itself — a task left uncompleted is
/// terminated by the system and counted against the app's future refresh budget; see
/// `SystemBackgroundSyncScheduler.registerLaunchHandler`'s doc for the full history). A lock-backed
/// `isDone` flag, not an actor: both call sites (`Task.cancel()`'s continuation and Apple's
/// `expirationHandler`) are synchronous, non-`async` contexts.
public final class BackgroundTaskCompletionGuard {
    private let lock = NSLock()
    private var isDone = false

    public init() {}

    /// Apple's expiration handler: "MUST set an expirationHandler that cancels the work AND calls
    /// setTaskCompleted(success: false)." A no-op — neither `cancelWork()` nor `setTaskCompleted`
    /// called — if the work already completed normally first.
    public func expire(_ task: BackgroundTaskCompleting) {
        guard markDoneIfNotAlready() else { return }
        task.cancelWork()
        task.setTaskCompleted(success: false)
    }

    /// The work's own natural completion. A no-op if the expiration handler already completed the
    /// task first — the realistic outcome given `cancelWork()`'s cooperative cancellation.
    public func complete(_ task: BackgroundTaskCompleting, success: Bool) {
        guard markDoneIfNotAlready() else { return }
        task.setTaskCompleted(success: success)
    }

    private func markDoneIfNotAlready() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isDone else { return false }
        isDone = true
        return true
    }
}
