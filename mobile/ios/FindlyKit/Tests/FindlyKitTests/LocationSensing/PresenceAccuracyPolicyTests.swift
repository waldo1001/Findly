import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §1.3/§3.4 (I52) — what `SystemLocationProvider` must do to the
/// single shared `CLLocationManager` once every pending `requestSingleFix` caller has resolved
/// (via timeout or a real delivery), depending on whether the §1.3 presence session is currently
/// running its own continuous `startUpdatingLocation()` stream on that SAME manager.
///
/// Two problems this exists to solve (both explicitly called out by I52's brief):
/// 1. The presence session sets `desiredAccuracy = kCLLocationAccuracyThreeKilometers` once at
///    start; a concurrent one-shot capture (the presence timer's own balanced tick, I51's locate
///    handler, the opportunistic BG-refresh trigger) can legitimately RAISE it while pending
///    (`PendingFixContinuations.registerAndAct` already guarantees this only ever raises, never
///    lowers, mid-flight). Nothing previously put it back down once every caller drained — so a
///    single locate would silently leave the standing presence session running at high accuracy
///    (GPS-class) forever after, defeating the entire point of the coarse baseline.
/// 2. `awaitNextLocation`'s timeout path cancels a stale `requestLocation()` via
///    `manager.stopUpdatingLocation()` — but that is the EXACT SAME call that would stop the
///    presence session's own continuous stream, since both share one `CLLocationManager`. Calling
///    it unconditionally while presence is active would silently kill presence every time a
///    one-shot capture happens to time out.
///
/// `drainAction` is the single pure rule both call sites (the `registerAndAct`-driven timeout
/// closure, and the `resumeAllAndAct`/`failAllAndAct` delivery closures) consult, so the decision
/// lives in one tested place rather than being re-derived at each call site.
struct PresenceAccuracyPolicyTests {

    @Test func noPresenceSession_stopsTheManagerOutright() {
        #expect(PresenceAccuracyPolicy.drainAction(presenceActive: false) == .stopUpdating)
    }

    @Test func presenceSessionRunning_neverStopsTheManager_onlyResetsAccuracy() {
        // Stopping here would kill the presence session's own continuous stream, not just cancel
        // the stale one-shot request — the exact defect this type exists to prevent.
        #expect(PresenceAccuracyPolicy.drainAction(presenceActive: true) == .resetAccuracyToPresenceBaseline)
    }
}
