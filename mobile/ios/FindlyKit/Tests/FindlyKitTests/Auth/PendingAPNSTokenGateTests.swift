import Testing
@testable import FindlyKit
import Foundation

/// specs/004-ios-client.md §4.1, I32 — with Firebase method swizzling disabled
/// (`FirebaseAppDelegateProxyEnabled = NO`), nothing auto-forwards the APNs device token to
/// `Auth` any more, and forwarding it unconditionally from the raw
/// `didRegisterForRemoteNotificationsWithDeviceToken` callback re-opens the `c725a41` trap:
/// `Auth.setAPNSToken` force-unwraps `tokenManager`, which is only assigned once Auth's async
/// `protectedDataInitialization()` has run, so an early callback traps. `PendingAPNSTokenGate` is
/// the Firebase-SDK-free readiness gate `FirebaseAuthProvider` (app target) wraps around the real
/// `Auth.setAPNSToken` call — pure Swift, so the readiness/pending semantics are fully
/// unit-testable here even though the SDK call itself only exists in the app target.
struct PendingAPNSTokenGateTests {
    private func token(_ byte: UInt8 = 0xAB) -> Data { Data([byte]) }

    @Test func offer_beforeReady_doesNotApply_soAnEarlyAPNsCallbackCannotTouchAuthAtAll() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []

        gate.offer(token()) { applied.append($0) }

        #expect(applied.isEmpty)
    }

    @Test func offer_afterReady_appliesImmediately() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []
        gate.markReady { applied.append($0) }

        gate.offer(token(), apply: { applied.append($0) })

        #expect(applied == [token()])
    }

    @Test func markReady_flushesAStashedToken_exactlyOnce() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []
        gate.offer(token(0x01)) { applied.append($0) }

        gate.markReady { applied.append($0) }

        #expect(applied == [token(0x01)])
    }

    /// Only the latest stashed token matters — a second `offer` before `markReady` ever runs
    /// overwrites the first, so the flush must deliver tokenB alone, exactly once. tokenA must
    /// never appear: it was superseded before there was ever a ready gate to apply it.
    @Test func offer_calledTwiceBeforeReady_onlyTheLatestTokenIsFlushed() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []
        gate.offer(token(0xA1)) { applied.append($0) }
        gate.offer(token(0xB2)) { applied.append($0) }

        gate.markReady { applied.append($0) }

        #expect(applied == [token(0xB2)])
    }

    @Test func markReady_withNoPendingToken_appliesNothing() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []

        gate.markReady { applied.append($0) }

        #expect(applied.isEmpty)
    }

    @Test func markReady_calledTwice_doesNotReapplyTheAlreadyFlushedToken() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []
        gate.offer(token(0x02)) { applied.append($0) }
        gate.markReady { applied.append($0) }

        gate.markReady { applied.append($0) }

        #expect(applied == [token(0x02)])
    }

    @Test func offer_calledAgainAfterReady_appliesTheNewTokenTooWithoutReapplyingTheOldOne() {
        let gate = PendingAPNSTokenGate()
        var applied: [Data] = []
        gate.offer(token(0x03)) { applied.append($0) }
        gate.markReady { applied.append($0) }

        gate.offer(token(0x04)) { applied.append($0) }

        #expect(applied == [token(0x03), token(0x04)])
    }

    /// I32 review Major 1 — reproduces the exact data race the internal `NSLock` exists to close:
    /// `offer` (main thread, the real UIKit callback) racing `markReady` (the global concurrent
    /// executor a `nonisolated async` function hops to before its first statement — this codebase's
    /// `startPhoneVerification`). Given the lock, EVERY interleaving of these two calls for a single
    /// token has exactly one legal outcome: either `offer` wins the race and stashes, then
    /// `markReady` flushes it — or `markReady` wins and flips ready first, so `offer` applies
    /// immediately. Both orderings deliver the token exactly once; without the lock, a classic
    /// lost-update interleaving (offer reads stale `isReady == false`, stashes; concurrently
    /// `markReady` reads the stash before offer's write is visible, flushes nothing) drops the token
    /// entirely — zero applies. Runs the race many times via `DispatchQueue.concurrentPerform` (a
    /// cheap stand-in for a ThreadSanitizer run) so a regression that removes the lock has a very
    /// high chance of being caught by an occasional `applied.count != 1` failure or a TSan report,
    /// rather than passing silently because a single run got lucky with scheduling.
    @Test func offerRacingMarkReady_underConcurrentAccess_alwaysDeliversExactlyOnce() {
        let trialCount = 2_000
        var failures: [String] = []
        let failuresLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: trialCount) { trial in
            let gate = PendingAPNSTokenGate()
            let expectedToken = token(UInt8(trial % 256))
            let appliedLock = NSLock()
            var applied: [Data] = []

            DispatchQueue.concurrentPerform(iterations: 2) { op in
                if op == 0 {
                    gate.offer(expectedToken) { delivered in
                        appliedLock.lock()
                        applied.append(delivered)
                        appliedLock.unlock()
                    }
                } else {
                    gate.markReady { delivered in
                        appliedLock.lock()
                        applied.append(delivered)
                        appliedLock.unlock()
                    }
                }
            }

            if applied != [expectedToken] {
                failuresLock.lock()
                failures.append("trial \(trial): expected [\(expectedToken)], got \(applied)")
                failuresLock.unlock()
            }
        }

        #expect(failures.isEmpty, "\(failures.count) of \(trialCount) racing trials misdelivered: \(failures.prefix(5))")
    }
}
