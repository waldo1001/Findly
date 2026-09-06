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
                #expect(!isFirst, "a second concurrent caller must NOT re-trigger requestLocation() - it rides the same in-flight platform request")
            }
        }
        while registry.count < 2 { Thread.sleep(forTimeInterval: 0.001) }

        registry.resumeAll { makeFix(source: $0) }
        first.cancel()
        second.cancel()
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

    @Test func timeOut_onAlreadyResumedId_isANoOp() async throws {
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

        // Resuming again (a race between a late timeout and the real answer) must not crash.
        registry.timeOut(id: id!, error: LocationProvidingError.timedOut)
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
