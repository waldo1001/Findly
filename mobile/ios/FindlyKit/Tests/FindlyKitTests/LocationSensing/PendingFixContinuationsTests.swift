import Testing
import Foundation
@testable import FindlyKit

/// specs/009-device-runtime.md §3.4 (I50 fix 5) — `SystemLocationProvider.awaitNextLocation` used
/// to stash a single `pendingFixContinuation`; a second concurrent `requestSingleFix` caller
/// silently overwrote it, leaking the first caller's continuation forever (it never resumes — a
/// permanent hung `Task`). I52's presence-session cadence timer and I51's `LOCATE_REQUEST` handler
/// both call `requestSingleFix` independently, making concurrent calls a realistic production
/// scenario, not a caller bug.
///
/// `PendingFixContinuations` is the CoreLocation-free bookkeeping this leak is fixed with — a
/// lock-protected registry (not an actor: `CLLocationManagerDelegate` callbacks are synchronous,
/// so a lock keeps registration and resume symmetric) so every registered caller resumes EXACTLY
/// once, whether via the real platform answer (`resumeAll`), a platform failure (`failAll`), or
/// its own independent per-source timeout (`timeOut`).
struct PendingFixContinuationsTests {

    private func makeFix(source: FixSource) -> LocationFix {
        LocationFix(fixId: "f", recordedAt: "2026-09-06T00:00:00Z", lat: 1, lon: 2, accuracyM: 5, batteryPct: 90, source: source)
    }

    @Test func register_reportsIsFirstOnlyForTheFirstConcurrentCaller() {
        let registry = PendingFixContinuations()

        let first = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (_, isFirst) = registry.register(source: .periodic, continuation: continuation)
                #expect(isFirst, "the first registration must report isFirst so the caller knows to actually call requestLocation()")
            }
        }
        while registry.count < 1 { Thread.sleep(forTimeInterval: 0.001) }

        let second = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (_, isFirst) = registry.register(source: .locate, continuation: continuation)
                // I50 fix 1: a `.locate` (high-tier) joiner MUST still report true here - it needs
                // its own, higher-accuracy `requestLocation()` re-issue, not a silent ride-along on
                // the already-in-flight `.periodic` (balanced-tier) request.
                #expect(isFirst, "a HIGHER-tier joiner (.locate over an in-flight .periodic) must still trigger its own requestLocation() re-issue")
            }
        }
        while registry.count < 2 { Thread.sleep(forTimeInterval: 0.001) }

        registry.resumeAll { makeFix(source: $0) }
        first.cancel()
        second.cancel()
    }

    @Test func register_equalOrLowerTierJoiner_doesNotReTriggerThePlatformRequest() {
        // The harmless, common case this dedup exists for: two `.periodic` (balanced) callers, or
        // a `.periodic` joining an in-flight `.locate` (high) - both ride along.
        let registry = PendingFixContinuations()

        let first = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (_, isFirst) = registry.register(source: .locate, continuation: continuation)
                #expect(isFirst)
            }
        }
        while registry.count < 1 { Thread.sleep(forTimeInterval: 0.001) }

        let second = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (_, isFirst) = registry.register(source: .periodic, continuation: continuation)
                #expect(!isFirst, "an equal-or-lower-tier joiner (.periodic over an in-flight .locate) must NOT re-trigger requestLocation() - it rides along for free")
            }
        }
        while registry.count < 2 { Thread.sleep(forTimeInterval: 0.001) }

        registry.resumeAll { makeFix(source: $0) }
        first.cancel()
        second.cancel()
    }

    @Test func register_blockingFinding_locateJoiningAnInFlightPeriodic_mustNotRideAlongUntagged() {
        // specs/009-device-runtime.md §1.1 (I50 review Blocking finding) - a `.locate` capture that
        // joins an in-flight `.periodic` request used to get a balanced (~100m) fix tagged
        // `source: "locate"`, because `register()` only ever looked at `pending.isEmpty`, not the
        // tier of what's already in flight. Regression-tests the exact reachable path: `FindlyApp`
        // hands ONE `SystemLocationProvider` to both the location runtime container (periodic/
        // significant-location-change captures) and `PushRuntimeContainer`'s
        // `LocateRequestPushHandler` (`.locate`).
        let registry = PendingFixContinuations()

        let periodicJoinedFirst = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .periodic, continuation: continuation)
            }
        }
        while registry.count < 1 { Thread.sleep(forTimeInterval: 0.001) }

        var locateNeedsPlatformRequest: Bool?
        let locateJoinsSecond = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (_, needsPlatformRequest) = registry.register(source: .locate, continuation: continuation)
                locateNeedsPlatformRequest = needsPlatformRequest
            }
        }
        while registry.count < 2 { Thread.sleep(forTimeInterval: 0.001) }

        #expect(locateNeedsPlatformRequest == true, "SystemLocationProvider relies on this to raise desiredAccuracy AND re-issue requestLocation() - otherwise the eventual delivery is the balanced fix, mistagged as a high-accuracy locate")

        registry.resumeAll { makeFix(source: $0) }
        periodicJoinedFirst.cancel()
        locateJoinsSecond.cancel()
    }

    @Test func resumeAll_resumesEveryPendingCallerWithItsOwnSource() async throws {
        let registry = PendingFixContinuations()

        let first = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .periodic, continuation: continuation)
            }
        }
        let second = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .locate, continuation: continuation)
            }
        }
        while registry.count < 2 { await Task.yield() }

        let resumedAny = registry.resumeAll { source in makeFix(source: source) }

        #expect(resumedAny)
        let firstFix = try await first.value
        let secondFix = try await second.value
        #expect(firstFix.source == .periodic)
        #expect(secondFix.source == .locate)
        #expect(registry.count == 0)
    }

    @Test func resumeAll_onEmptyRegistry_returnsFalseAndResumesNothing() {
        let registry = PendingFixContinuations()
        let resumedAny = registry.resumeAll { source in makeFix(source: source) }
        #expect(!resumedAny)
    }

    @Test func timeOut_resumesOnlyItsOwnCaller_leavingOthersPending() async throws {
        let registry = PendingFixContinuations()

        var idA: PendingFixContinuations.ID?
        let a = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (id, _) = registry.register(source: .geofence, continuation: continuation)
                idA = id
            }
        }
        let b = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .periodic, continuation: continuation)
            }
        }
        while registry.count < 2 { await Task.yield() }
        while idA == nil { await Task.yield() }

        registry.timeOut(id: idA!, error: LocationProvidingError.timedOut)

        do {
            _ = try await a.value
            Issue.record("expected the timed-out caller to throw")
        } catch let error as LocationProvidingError {
            #expect(error == .timedOut)
        }
        #expect(registry.count == 1, "the other, still-waiting caller must not be disturbed by a timeout that isn't its own")

        // The real platform answer still eventually resumes the survivor.
        let resumedAny = registry.resumeAll { source in makeFix(source: source) }
        #expect(resumedAny)
        let bFix = try await b.value
        #expect(bFix.source == .periodic)
    }

    @Test func timeOut_ofTheLastPendingCaller_reportsTheRegistryIsNowEmpty() async throws {
        // I50 fix 8 - `SystemLocationProvider` uses this to cancel CoreLocation's still in-flight
        // `requestLocation()` (`manager.stopUpdatingLocation()`) the moment every caller has given
        // up, so a stray late delivery doesn't fall through to the significant-location-change hint
        // path mislabeled `.periodic` (specs/001 §5.1: `source` should say what triggered the
        // capture).
        let registry = PendingFixContinuations()
        var id: PendingFixContinuations.ID?
        let task = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (registeredId, _) = registry.register(source: .locate, continuation: continuation)
                id = registeredId
            }
        }
        while registry.count < 1 { await Task.yield() }

        let isNowEmpty = registry.timeOut(id: id!, error: LocationProvidingError.timedOut)

        #expect(isNowEmpty, "the only pending caller just timed out - nothing is left waiting on the in-flight platform request")
        do {
            _ = try await task.value
            Issue.record("expected the timed-out caller to throw")
        } catch let error as LocationProvidingError {
            #expect(error == .timedOut)
        }
    }

    @Test func timeOut_whileAnotherCallerStillPending_reportsTheRegistryIsNotEmpty() async {
        let registry = PendingFixContinuations()
        var idA: PendingFixContinuations.ID?
        let a = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (id, _) = registry.register(source: .periodic, continuation: continuation)
                idA = id
            }
        }
        let b = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .locate, continuation: continuation)
            }
        }
        while registry.count < 2 { await Task.yield() }
        while idA == nil { await Task.yield() }

        let isNowEmpty = registry.timeOut(id: idA!, error: LocationProvidingError.timedOut)

        #expect(!isNowEmpty, "the .locate caller is still waiting - the in-flight platform request must NOT be cancelled out from under it")

        registry.resumeAll { makeFix(source: $0) }
        a.cancel()
        b.cancel()
    }

    @Test func timeOut_onAlreadyResumedId_reportsFalse_andRemainsANoOp() async throws {
        let registry = PendingFixContinuations()
        var id: PendingFixContinuations.ID?
        let task = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let (registeredId, _) = registry.register(source: .manual, continuation: continuation)
                id = registeredId
            }
        }
        while registry.count < 1 { await Task.yield() }

        #expect(registry.resumeAll { source in makeFix(source: source) })
        let fix = try await task.value
        #expect(fix.source == .manual)

        // Resuming again (a race between a late timeout and the real answer) must not crash, and
        // must report `false` - this call didn't newly empty the registry (there was nothing left
        // here to remove), so the caller must NOT cancel a platform request on its account.
        let isNowEmpty = registry.timeOut(id: id!, error: LocationProvidingError.timedOut)
        #expect(!isNowEmpty)
    }

    // MARK: - I50 second-round review, Major: register-then-act / timeOut-then-act atomicity
    //
    // `register()`/`timeOut()` above correctly compute `needsPlatformRequest`/`isNowEmpty`, but
    // `SystemLocationProvider.awaitNextLocation` used to act on those results (`desiredAccuracy` +
    // `requestLocation()`, or `stopUpdatingLocation()`) AFTER releasing the lock. Nothing then
    // prevented a second, genuinely concurrent caller's own act-on-the-manager from interleaving
    // with it - whichever CoreLocation mutation landed last silently won, independent of which
    // caller's tier was actually higher (Apple documents that a new `requestLocation()` cancels the
    // previous one). `registerAndAct`/`timeOutAndAct` close that gap by running the caller-supplied
    // action WHILE STILL HOLDING the lock, so two such actions - from any mix of the two methods,
    // since both share the same internal lock - can never interleave.
    //
    // `EventRecorder`/`makeSynchronousContinuation` below let these tests drive real, concurrent
    // `Thread`s (not cooperating `Task`s on a shared pool) at genuinely the same moment, and record
    // exactly when each action starts/ends so the tests can assert no two actions ever overlap.

    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        func record(_ event: String) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }
        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }
    }

    /// Bridges a real `CheckedContinuation` out of `withCheckedThrowingContinuation` synchronously,
    /// so a plain `Thread` (not an `async` context) can call `registerAndAct`/`timeOutAndAct`
    /// directly. The started `Task` is intentionally discarded - it is already scheduled and keeps
    /// itself alive until `resumeAll`/`failAll` resolves it at the end of each test.
    private final class ContinuationBox: @unchecked Sendable {
        var continuation: CheckedContinuation<LocationFix, Error>?
    }

    private func makeSynchronousContinuation() -> CheckedContinuation<LocationFix, Error> {
        let box = ContinuationBox()
        let handoff = DispatchSemaphore(value: 0)
        Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                box.continuation = continuation
                handoff.signal()
            }
        }
        handoff.wait()
        return box.continuation!
    }

    /// Asserts the recorded events never show one label's action starting while another label's
    /// action is still running - the core atomicity guarantee `registerAndAct`/`timeOutAndAct`
    /// exist for. Passes whether one or both actions actually fired (which of the two concurrent
    /// callers "needs" to act is a legitimate outcome of the tier-comparison rule tested above,
    /// not what this check is about); it fails only on genuine interleaving.
    private func assertNoInterleaving(_ events: [String]) {
        var active: Set<String> = []
        for event in events {
            let parts = event.split(separator: "-")
            let label = String(parts[0])
            if parts[1] == "start" {
                #expect(active.isEmpty, "\(event) fired while \(active) was still running - actions must be mutually exclusive")
                active.insert(label)
            } else {
                #expect(active.contains(label), "\(event) fired without a matching start")
                active.remove(label)
            }
        }
        #expect(active.isEmpty, "an action never reached its end event")
        #expect(!events.isEmpty, "expected at least one caller's action to actually run")
    }

    @Test func registerAndAct_serializesItsActionAgainstAConcurrentRegisterAndActCall() {
        // What this proves: two `registerAndAct` calls made from genuinely different OS threads at
        // the same moment never run their actions concurrently - the recorded events never
        // interleave, regardless of which caller's action(s) actually fire.
        // What this does NOT prove: that the real `CLLocationManager.desiredAccuracy` /
        // `requestLocation()` calls behave correctly once serialized this way -
        // `SystemLocationProvider` is `#if os(iOS) && canImport(CoreLocation)` platform glue this
        // suite cannot compile on macOS, let alone exercise; only the registry-level mutual
        // exclusion is verified here.
        let registry = PendingFixContinuations()
        let recorder = EventRecorder()
        let continuationA = makeSynchronousContinuation()
        let continuationB = makeSynchronousContinuation()
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)

        let threadA = Thread {
            ready.signal()
            start.wait()
            registry.registerAndAct(source: .periodic, continuation: continuationA) {
                recorder.record("A-start")
                Thread.sleep(forTimeInterval: 0.05)
                recorder.record("A-end")
            }
        }
        let threadB = Thread {
            ready.signal()
            start.wait()
            registry.registerAndAct(source: .locate, continuation: continuationB) {
                recorder.record("B-start")
                Thread.sleep(forTimeInterval: 0.05)
                recorder.record("B-end")
            }
        }
        threadA.start()
        threadB.start()
        ready.wait()
        ready.wait()
        start.signal()
        start.signal()
        while !threadA.isFinished || !threadB.isFinished { Thread.sleep(forTimeInterval: 0.001) }

        assertNoInterleaving(recorder.all)

        registry.failAll(with: LocationProvidingError.timedOut)
    }

    @Test func registerAndAct_serializesItsActionAgainstAConcurrentTimeOutAndActCall() {
        // Covers the second face of the same finding: fix 8's belated `stopUpdatingLocation()`
        // (`timeOutAndAct`'s action) racing a brand-new caller's `register()` + `requestLocation()`
        // (`registerAndAct`'s action). An existing caller is registered up front (not part of the
        // race) and its timeout races a second, brand-new caller's registration.
        let registry = PendingFixContinuations()
        let recorder = EventRecorder()
        let existingContinuation = makeSynchronousContinuation()
        let (existingId, _) = registry.register(source: .periodic, continuation: existingContinuation)
        let newContinuation = makeSynchronousContinuation()
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)

        let timeOutThread = Thread {
            ready.signal()
            start.wait()
            registry.timeOutAndAct(id: existingId, error: LocationProvidingError.timedOut) {
                recorder.record("stop-start")
                Thread.sleep(forTimeInterval: 0.05)
                recorder.record("stop-end")
            }
        }
        let registerThread = Thread {
            ready.signal()
            start.wait()
            registry.registerAndAct(source: .locate, continuation: newContinuation) {
                recorder.record("request-start")
                Thread.sleep(forTimeInterval: 0.05)
                recorder.record("request-end")
            }
        }
        timeOutThread.start()
        registerThread.start()
        ready.wait()
        ready.wait()
        start.signal()
        start.signal()
        while !timeOutThread.isFinished || !registerThread.isFinished { Thread.sleep(forTimeInterval: 0.001) }

        assertNoInterleaving(recorder.all)

        registry.failAll(with: LocationProvidingError.timedOut)
    }

    @Test func failAll_resumesEveryPendingCallerWithTheSameError() async throws {
        let registry = PendingFixContinuations()
        let a = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .periodic, continuation: continuation)
            }
        }
        let b = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .locate, continuation: continuation)
            }
        }
        while registry.count < 2 { await Task.yield() }

        registry.failAll(with: LocationProvidingError.underlying("kCLErrorLocationUnknown"))

        for task in [a, b] {
            do {
                _ = try await task.value
                Issue.record("expected both pending callers to throw")
            } catch let error as LocationProvidingError {
                #expect(error == .underlying("kCLErrorLocationUnknown"))
            }
        }
        #expect(registry.count == 0)
    }

    // MARK: - I52 item 3: resumeAllAndAct/failAllAndAct — the drain-time accuracy/presence action
    // must run INSIDE the same critical section register/timeOutAndAct already share, for exactly
    // the reason those two exist: a concurrent caller registering a brand-new higher-tier request
    // in the gap between "the registry just drained" and "the caller acted on that" must never be
    // able to interleave with the act. `resumeAll`/`failAll` above are UNCHANGED (existing callers/
    // tests keep working) - these are additive atomic counterparts, mirroring registerAndAct/
    // timeOutAndAct's own shape exactly.

    @Test func resumeAllAndAct_runsTheActionOnlyWhenSomethingWasActuallyPending() async throws {
        let registry = PendingFixContinuations()

        let notDrained = registry.resumeAllAndAct(makeFix: { makeFix(source: $0) }, ifDrained: {
            Issue.record("must not run - nothing was pending")
        })
        #expect(!notDrained)

        let task = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .periodic, continuation: continuation)
            }
        }
        while registry.count < 1 { await Task.yield() }

        var actionRan = false
        let drained = registry.resumeAllAndAct(makeFix: { makeFix(source: $0) }, ifDrained: { actionRan = true })
        #expect(drained)
        #expect(actionRan)
        let fix = try await task.value
        #expect(fix.source == .periodic)
        #expect(registry.count == 0)
    }

    @Test func failAllAndAct_runsTheActionOnlyWhenSomethingWasActuallyPending() async throws {
        let registry = PendingFixContinuations()

        let notDrained = registry.failAllAndAct(with: LocationProvidingError.timedOut, ifDrained: {
            Issue.record("must not run - nothing was pending")
        })
        #expect(!notDrained)

        let task = Task<LocationFix, Error> {
            try await withCheckedThrowingContinuation { continuation in
                registry.register(source: .locate, continuation: continuation)
            }
        }
        while registry.count < 1 { await Task.yield() }

        var actionRan = false
        let drained = registry.failAllAndAct(with: LocationProvidingError.underlying("kCLErrorLocationUnknown"), ifDrained: { actionRan = true })
        #expect(drained)
        #expect(actionRan)
        do {
            _ = try await task.value
            Issue.record("expected the pending caller to throw")
        } catch let error as LocationProvidingError {
            #expect(error == .underlying("kCLErrorLocationUnknown"))
        }
    }

    @Test func resumeAllAndAct_serializesItsActionAgainstAConcurrentRegisterAndActCall() {
        // The exact concurrency property registerAndAct/timeOutAndAct already prove for each
        // other, extended to resumeAllAndAct: a delivery draining the registry and a brand-new
        // caller registering at the same moment must never run their actions concurrently.
        let registry = PendingFixContinuations()
        let recorder = EventRecorder()
        let existingContinuation = makeSynchronousContinuation()
        registry.register(source: .periodic, continuation: existingContinuation)
        let newContinuation = makeSynchronousContinuation()
        let ready = DispatchSemaphore(value: 0)
        let start = DispatchSemaphore(value: 0)

        let resumeThread = Thread {
            ready.signal()
            start.wait()
            registry.resumeAllAndAct(makeFix: { self.makeFix(source: $0) }, ifDrained: {
                recorder.record("resume-start")
                Thread.sleep(forTimeInterval: 0.05)
                recorder.record("resume-end")
            })
        }
        let registerThread = Thread {
            ready.signal()
            start.wait()
            registry.registerAndAct(source: .locate, continuation: newContinuation) {
                recorder.record("request-start")
                Thread.sleep(forTimeInterval: 0.05)
                recorder.record("request-end")
            }
        }
        resumeThread.start()
        registerThread.start()
        ready.wait()
        ready.wait()
        start.signal()
        start.signal()
        while !resumeThread.isFinished || !registerThread.isFinished { Thread.sleep(forTimeInterval: 0.001) }

        assertNoInterleaving(recorder.all)

        registry.failAll(with: LocationProvidingError.timedOut)
    }
}
