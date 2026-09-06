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
}
