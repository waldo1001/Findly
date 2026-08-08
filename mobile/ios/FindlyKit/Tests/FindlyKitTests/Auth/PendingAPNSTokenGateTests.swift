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
}
