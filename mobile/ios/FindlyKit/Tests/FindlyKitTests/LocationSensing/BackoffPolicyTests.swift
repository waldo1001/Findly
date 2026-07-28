import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §9 — transient-flush-failure backoff: exponential, 30 s initial,
/// doubling, capped at the sync interval ("never back off past the next natural capture").
struct BackoffPolicyTests {

    @Test func firstAttempt_is30Seconds() {
        #expect(BackoffPolicy.delay(forAttempt: 1, syncIntervalMinutes: 60) == 30)
    }

    @Test func delayDoublesEachAttempt() {
        #expect(BackoffPolicy.delay(forAttempt: 2, syncIntervalMinutes: 60) == 60)
        #expect(BackoffPolicy.delay(forAttempt: 3, syncIntervalMinutes: 60) == 120)
        #expect(BackoffPolicy.delay(forAttempt: 4, syncIntervalMinutes: 60) == 240)
    }

    @Test func delayIsCappedAtTheSyncIntervalInSeconds() {
        // syncIntervalMinutes=5 -> cap 300s; attempt 5 would otherwise be 30*2^4=480s.
        #expect(BackoffPolicy.delay(forAttempt: 5, syncIntervalMinutes: 5) == 300)
    }

    @Test func neverExceedsTheCapEvenForPathologicallyLargeAttempts() {
        #expect(BackoffPolicy.delay(forAttempt: 1000, syncIntervalMinutes: 15) == 900)
    }
}
