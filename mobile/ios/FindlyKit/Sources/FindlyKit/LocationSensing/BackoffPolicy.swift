import Foundation

/// specs/009-device-runtime.md §9 — transient-flush-failure backoff: "exponential — 30 s initial,
/// doubling, capped at the sync interval (never back off past the next natural capture)." Pure,
/// standalone bookkeeping is needed on iOS because none of the three §3.4 triggers is a
/// WorkManager-style scheduler with native backoff support — `LocationSyncRunner` tracks its own
/// consecutive-failure attempt count and consults this before asking `BackgroundSyncScheduling` to
/// reschedule.
public enum BackoffPolicy {
    private static let initialDelaySeconds: TimeInterval = 30
    private static let maxShift = 20 // guards against overflow on a pathologically large attempt count

    /// `attempt` is 1-based (the first retry is attempt 1). Returns the delay in seconds.
    public static func delay(forAttempt attempt: Int, syncIntervalMinutes: Int) -> TimeInterval {
        precondition(attempt >= 1, "attempt must be >= 1, was \(attempt)")
        let capSeconds = TimeInterval(syncIntervalMinutes) * 60
        let shift = min(attempt - 1, maxShift)
        let exponential = initialDelaySeconds * pow(2, Double(shift))
        return min(exponential, capSeconds)
    }
}
