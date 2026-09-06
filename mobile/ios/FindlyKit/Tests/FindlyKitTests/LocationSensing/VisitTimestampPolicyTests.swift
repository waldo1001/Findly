import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §3.4 (I50 fix 3, Major) — `CLVisit` is reported at DEPARTURE, so the
/// timestamp attached to its derived fix must prefer `departureDate` (nearest to "now", when the
/// callback actually fires) over `arrivalDate` (specs/001 §5.1's "only if newer than the stored
/// one" last-known-position rule otherwise silently drops an eight-hour-stale fix - it still
/// appends fine to history, only the family map's last-known position update is defeated). `CLVisit`
/// uses `Date.distantFuture`/`.distantPast` as its own documented "unknown" sentinels for
/// `departureDate`/`arrivalDate` respectively - neither sentinel can ever reach the computed
/// timestamp. Mirrors `BackgroundLocationPolicy`'s split: pure decision logic, CoreLocation-free,
/// tested here; `SystemLocationProvider`'s `didVisit` delegate callback (untestable on macOS,
/// `#if os(iOS) && canImport(CoreLocation)`) is the one, thin call site.
struct VisitTimestampPolicyTests {

    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func departureKnown_prefersDeparture_evenWhenArrivalIsAlsoKnown() {
        // The Major finding's core scenario: an eight-hour stay reported at departure. Preferring
        // arrivalDate (the old order) would stamp the fix eight hours stale.
        let arrival = now.addingTimeInterval(-8 * 60 * 60)
        let departure = now

        let timestamp = VisitTimestampPolicy.timestamp(arrivalDate: arrival, departureDate: departure, now: now)

        #expect(timestamp == departure)
    }

    @Test func departureUnknown_fallsBackToArrival() {
        // A departure-only... no - an ARRIVAL-only visit (ongoing, or a departure CLVisit never
        // resolves): departureDate is CLVisit's own distantFuture sentinel.
        let arrival = now.addingTimeInterval(-30)

        let timestamp = VisitTimestampPolicy.timestamp(arrivalDate: arrival, departureDate: .distantFuture, now: now)

        #expect(timestamp == arrival)
    }

    @Test func ongoingVisit_arrivalApproximatelyNow_departureUnknown_staysCorrect() {
        // The already-correct case the reviewer confirmed must not regress: an ONGOING visit fires
        // at arrival, where arrivalDate is approximately now and departureDate is still unknown.
        let timestamp = VisitTimestampPolicy.timestamp(arrivalDate: now, departureDate: .distantFuture, now: now)

        #expect(timestamp == now)
    }

    @Test func bothUnknown_fallsBackToNow() {
        let timestamp = VisitTimestampPolicy.timestamp(arrivalDate: .distantPast, departureDate: .distantFuture, now: now)

        #expect(timestamp == now)
    }

    @Test func arrivalUnknown_departureKnown_prefersDeparture() {
        // A departure-only visit: CLVisit's own distantPast sentinel for an unknown arrivalDate.
        let departure = now.addingTimeInterval(-5)

        let timestamp = VisitTimestampPolicy.timestamp(arrivalDate: .distantPast, departureDate: departure, now: now)

        #expect(timestamp == departure)
    }

    @Test func clockSkewDefence_neverReturnsATimestampAfterNow() {
        // specs/001 §5.1's clock-skew rejection rule (a recordedAt in the future is invalid) -
        // defence-in-depth even though neither real CLVisit field should ever be ahead of "now".
        let future = now.addingTimeInterval(60)

        let timestamp = VisitTimestampPolicy.timestamp(arrivalDate: future, departureDate: .distantFuture, now: now)

        #expect(timestamp == now, "must clamp to now, never report a future recordedAt")
    }
}
