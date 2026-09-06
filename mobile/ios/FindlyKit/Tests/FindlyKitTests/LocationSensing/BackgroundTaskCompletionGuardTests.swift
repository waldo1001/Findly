import Testing
@testable import FindlyKit

private final class FakeBackgroundTaskCompleting: BackgroundTaskCompleting {
    private(set) var cancelWorkCallCount = 0
    private(set) var completions: [Bool] = []
    func cancelWork() { cancelWorkCallCount += 1 }
    func setTaskCompleted(success: Bool) { completions.append(success) }
}

/// specs/009-device-runtime.md §3.4 (I50 fix 4, Major) — `BGTask.setTaskCompleted` MUST be called
/// at most once. `LocationSyncScheduler`'s registered launch handler used to call it from two
/// unsynchronized places (the work's own natural completion, and the expiration handler), and
/// `work.cancel()` is cooperative: `LocationSyncRunner.runOnce()` awaits network I/O with no
/// cancellation checks, so it typically finishes AFTER expiration already completed the task —
/// completing a `BGTask` twice is API misuse whose failure mode is exactly the background-budget
/// starvation this fix exists to stop. `BackgroundTaskCompletionGuard` is the pure "first call
/// wins" guard behind both call sites, tested here over the tiny `BackgroundTaskCompleting`
/// protocol (real production conformance is `BGAppRefreshTask`/`Task.cancel()` glue, `#if os(iOS)
/// && canImport(BackgroundTasks)`, untestable on macOS) so the property this fix actually cares
/// about — exactly one `setTaskCompleted` call, ever — is unit-tested directly rather than only
/// implied by the untestable glue around it.
struct BackgroundTaskCompletionGuardTests {

    @Test func expiration_cancelsTheWorkAndCompletesExactlyOnceWithFalse() {
        let task = FakeBackgroundTaskCompleting()
        let completionGuard = BackgroundTaskCompletionGuard()

        completionGuard.expire(task)

        #expect(task.cancelWorkCallCount == 1)
        #expect(task.completions == [false])
    }

    @Test func lateWorkCompletion_afterExpiration_isANoOp() {
        // The exact race this fix closes: the work finishes normally AFTER the expiration handler
        // already completed the task.
        let task = FakeBackgroundTaskCompleting()
        let completionGuard = BackgroundTaskCompletionGuard()

        completionGuard.expire(task)
        completionGuard.complete(task, success: true)

        #expect(task.completions == [false], "a late success completion after expiration must never call setTaskCompleted a second time")
    }

    @Test func normalCompletion_whenNeverExpired_completesWithTheGivenValue_andNeverCancels() {
        let task = FakeBackgroundTaskCompleting()
        let completionGuard = BackgroundTaskCompletionGuard()

        completionGuard.complete(task, success: true)

        #expect(task.cancelWorkCallCount == 0)
        #expect(task.completions == [true])
    }

    @Test func expiration_afterNormalCompletion_isANoOp() {
        let task = FakeBackgroundTaskCompleting()
        let completionGuard = BackgroundTaskCompletionGuard()

        completionGuard.complete(task, success: true)
        completionGuard.expire(task)

        #expect(task.cancelWorkCallCount == 0, "the work already completed normally - a later expiration must not cancel or re-complete it")
        #expect(task.completions == [true])
    }
}
