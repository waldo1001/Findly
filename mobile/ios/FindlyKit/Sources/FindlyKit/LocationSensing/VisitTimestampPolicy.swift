import Foundation

/// specs/009-device-runtime.md §3.4 (I50 fix 3, Major) — which `CLVisit` date to stamp its derived
/// fix with. Pure and CoreLocation-free (only `Foundation`/`Date`) so it's testable on any host,
/// unlike `SystemLocationProvider`'s `didVisit` delegate callback itself (`#if os(iOS) &&
/// canImport(CoreLocation)`, platform glue `swift test` cannot exercise) — mirrors
/// `BackgroundLocationPolicy`'s split.
///
/// **Prefer the LATER known date, not `arrivalDate` first.** iOS reports a completed visit at
/// DEPARTURE — the previous "arrival, then departure" fallback order meant a visit ending after an
/// eight-hour stay produced a fix timestamped eight hours in the past. specs/001 §5.1 updates
/// last-known "only if the batch's newest `recordedAt` is newer than the stored one", so that fix
/// was silently inert for the family map (it still appended fine to history — only the
/// last-known-position update was defeated), defeating specs/009 §3.4's whole point in adding visit
/// monitoring as a second free wake. Preferring departure fixes this AND stays correct for the
/// already-working case: an ONGOING visit fires at arrival, where `arrivalDate` is approximately
/// now and `departureDate` is still `CLVisit`'s own `.distantFuture` "unknown" sentinel — so it
/// naturally falls through to the `arrivalDate` branch. `.distantPast`/`.distantFuture` are
/// `CLVisit`'s documented sentinels for "unknown" `arrivalDate`/`departureDate` respectively;
/// neither can ever reach the returned timestamp.
public enum VisitTimestampPolicy {
    public static func timestamp(arrivalDate: Date, departureDate: Date, now: Date) -> Date {
        let timestamp: Date
        if departureDate != Date.distantFuture {
            timestamp = departureDate
        } else if arrivalDate != Date.distantPast {
            timestamp = arrivalDate
        } else {
            timestamp = now
        }
        // Defence-in-depth against specs/001 §5.1's clock-skew rejection rule (a `recordedAt` in
        // the future is invalid) - neither real CLVisit field should ever be ahead of "now", but
        // clamping costs nothing and removes the question entirely.
        return min(timestamp, now)
    }
}
