import Foundation
@testable import FindlyKit

/// A test-only stand-in for a real `sleep` that behaves like one in the two ways a poll/timer loop
/// depends on, and that `SleepGate` (one-shot, never wakes on cancellation) does not:
///
/// - a parked sleep **returns early when its task is cancelled** (like `Task.sleep`, whose
///   cancellation the app's `try? await Task.sleep(nanoseconds:)` swallows), so a timer that the code
///   under test cancelled is observably gone — `parkedCount` drops — instead of lingering and
///   swallowing the next release;
/// - `fire()` is "30 seconds pass": it wakes **every** currently parked sleep, the way a real clock
///   would have woken sleeps that all began at about the same time.
///
/// Tests synchronise on `parkedCount` (via `waitUntil`) rather than on wall-clock sleeps, so there is
/// no race between "the timer task has not started yet" and "fire() found nobody to wake".
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var requested: [Duration] = []

    /// Every duration a sleep was started with, in call order (cancelled sleeps included).
    var requestedDurations: [Duration] {
        lock.withLock { requested }
    }

    /// How many sleeps are parked right now.
    var parkedCount: Int {
        lock.withLock { parked.count }
    }

    func sleep(_ duration: Duration) async {
        let id = UUID()
        lock.withLock { requested.append(duration) }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow: Bool = lock.withLock {
                    if Task.isCancelled { return true }
                    parked[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let continuation = lock.withLock { parked.removeValue(forKey: id) }
            continuation?.resume()
        }
    }

    /// Time passes: every parked sleep returns.
    func fire() {
        let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
            let all = Array(parked.values)
            parked.removeAll()
            return all
        }
        continuations.forEach { $0.resume() }
    }
}

/// Records every fetch a `MapRefreshDriver` was asked to perform. When `gate` is set the NEXT
/// `perform` parks on it until released, which is how a test holds one fetch "in flight" while it
/// throws further triggers at the driver.
@MainActor
final class RefreshRecorder {
    private(set) var triggers: [MapRefreshPolicy.Trigger] = []
    var gate: SleepGate?

    func perform(_ trigger: MapRefreshPolicy.Trigger) async {
        triggers.append(trigger)
        if let gate {
            self.gate = nil
            await gate.wait()
        }
    }
}
