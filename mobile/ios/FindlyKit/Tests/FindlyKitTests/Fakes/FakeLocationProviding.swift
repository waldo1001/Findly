import Foundation
@testable import FindlyKit

/// A shared `LocationProviding` fake — `FixCaptureCoordinator`'s only collaborator that touches
/// CoreLocation in production (specs/009-device-runtime.md §12: "pure, unit-tested
/// decision/coordination logic... no platform framework in unit tests"). Used by
/// `FixCaptureCoordinatorTests` (indirectly, via its own local fake) and directly by
/// `LocationSyncRunnerTests`/`LocationRuntimeContainerTests`.
final class FakeLocationProviding: LocationProviding {
    var nextFix: Result<LocationFix, Error> = .failure(LocationProvidingError.notImplemented)

    /// specs/009 §7 — defaults to `.always` because these fakes stand in for a device whose user
    /// has already granted permission, which is the precondition every monitoring/capture test here
    /// is actually about. The protocol's own default is `.notDetermined` (correct for a real
    /// provider that has not asked yet), and inheriting that would make every such test silently
    /// assert the permission gate rather than the behaviour it was written for. Set it explicitly
    /// to exercise the gate itself.
    var authorization: LocationAuthorization = .always

    private(set) var requestSingleFixCalls: [FixSource] = []
    private(set) var startBackgroundMonitoringCallCount = 0
    private(set) var stopBackgroundMonitoringCallCount = 0

    /// specs/009-device-runtime.md §1.3 (I52) — every `startPresence` call's interval, in order,
    /// so a test can assert both "presence was (not) started" and "with which interval".
    private(set) var startPresenceCalls: [Int] = []
    private(set) var stopPresenceCallCount = 0
    /// The most recent `onTick` closure handed to `startPresence`, so a test can simulate the
    /// presence session's own cadence timer firing without a real `Timer`.
    private(set) var lastPresenceOnTick: (() -> Void)?

    /// specs/009 §1.3 (I52 review round 2, finding 1) — `Thread.isMainThread` captured at the
    /// instant each `startPresence`/`stopPresence` call actually lands here, so a test can prove
    /// the presence lifecycle reaches this seam already hopped onto the main thread — the Blocking
    /// finding's own reproduction was "the closure... runs on the actor's cooperative-pool
    /// executor", which this array makes directly observable without CoreLocation/a real `Timer`.
    private(set) var startPresenceCalledOnMainThread: [Bool] = []
    private(set) var stopPresenceCalledOnMainThread: [Bool] = []

    /// specs/009 §1.3/§12 (I52 review round 2, finding 5) — real idempotency/interval-change state,
    /// mirroring what `SystemLocationProvider`'s own `presenceTimer`/`presenceIntervalMinutes`
    /// pairing must track: `nil` when no presence session is active, the most recently (re)started
    /// interval otherwise. Previously this fake appended unconditionally and modeled no state at
    /// all, so no container-level test could observe idempotency (finding 2's regression) or an
    /// interval change — this property, plus the idempotency/rebuild logic in `startPresence`
    /// below, are what close that gap.
    private(set) var activeIntervalMinutes: Int?

    func requestSingleFix(source: FixSource) async throws -> LocationFix {
        requestSingleFixCalls.append(source)
        return try nextFix.get()
    }

    func startBackgroundMonitoring(coordinator: FixCaptureCoordinator) {
        startBackgroundMonitoringCallCount += 1
    }

    func stopBackgroundMonitoring() {
        stopBackgroundMonitoringCallCount += 1
    }

    /// Mirrors `SystemLocationProvider.startPresence`'s finding-2 contract exactly: a call at the
    /// SAME interval as the currently-active session is a genuine no-op (specs/009 §1.3
    /// "establishing presence is idempotent"); a call at a DIFFERENT interval while a session is
    /// already active tears it down first (mirroring `stopPresence()`) and rebuilds (specs/009 §3.5
    /// "if syncIntervalMinutes changed the schedule MUST be rebuilt immediately").
    /// `startPresenceCalledOnMainThread` still records the thread for EVERY call attempt, including
    /// a suppressed one, since that check (finding 1) is orthogonal to whether the call did anything.
    func startPresence(syncIntervalMinutes: Int, onTick: @escaping () -> Void) {
        startPresenceCalledOnMainThread.append(Thread.isMainThread)
        if let active = activeIntervalMinutes {
            guard active != syncIntervalMinutes else { return } // idempotent no-op
            stopPresence() // interval changed while live -> tear down and rebuild
        }
        startPresenceCalls.append(syncIntervalMinutes)
        lastPresenceOnTick = onTick
        activeIntervalMinutes = syncIntervalMinutes
    }

    func stopPresence() {
        stopPresenceCalledOnMainThread.append(Thread.isMainThread)
        stopPresenceCallCount += 1
        activeIntervalMinutes = nil
    }
}
