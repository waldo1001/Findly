import Foundation

/// specs/009-device-runtime.md §3.4 (I50 fix 1 + fix 3) — the two Always-gated decisions behind
/// iOS's silent background-capture failures, expressed as pure `LocationAuthorization` → `Bool`
/// functions so they're unit-testable without `CoreLocation` (`SystemLocationProvider` itself is
/// platform glue, `#if os(iOS) && canImport(CoreLocation)`, and cannot be exercised in `swift
/// test`).
///
/// Both rules happen to reduce to the same predicate today (`authorization == .always`), but are
/// kept as two separately named, separately tested functions rather than one shared boolean: each
/// answers a different §3.4 bullet ("background delivery of one-shot requests" vs. "significant-
/// location-change monitoring needs Always") and nothing says they must stay identical forever —
/// collapsing them into one name would make a future divergence a silent one-line change instead
/// of a reviewed rename.
public enum BackgroundLocationPolicy {
    /// specs/009 §3.4 "Background delivery of one-shot requests": any `CLLocationManager` used for
    /// `requestLocation()` outside the foreground MUST have `allowsBackgroundLocationUpdates =
    /// true` set **whenever authorization is Always**, and reset to `false` the moment it drops
    /// below Always (setting it without the permission is a CoreLocation runtime error, so this
    /// function is the one place that decision is allowed to be made).
    public static func allowsBackgroundLocationUpdates(for authorization: LocationAuthorization) -> Bool {
        authorization == .always
    }

    /// specs/009 §3.4 "Significant-location-change monitoring": "MUST be started only with Always
    /// authorization (When-In-Use cannot wake a suspended app; starting it earlier only misleads
    /// the permission banner logic)." Also governs `startMonitoringVisits()` (§3.4's second cheap
    /// wake, amended 2026-09-06) — both mechanisms exist to wake a SUSPENDED app, which When-In-Use
    /// cannot do, so they share this one gate.
    public static func shouldMonitorSignificantChangesAndVisits(for authorization: LocationAuthorization) -> Bool {
        authorization == .always
    }
}
