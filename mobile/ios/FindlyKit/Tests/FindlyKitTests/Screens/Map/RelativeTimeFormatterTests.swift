import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1: roster subtitles render humanized relative times
/// ("24 min ago") instead of raw ISO strings, recomputed on a 30 s ticker (never per frame) — the
/// ticker itself is UI plumbing (`LiveMapScreen`), but the formula it calls is pure, shared logic,
/// unit tested here with no SwiftUI/Foundation-clock dependency (§10's test checklist:
/// "thresholds ('just now' / minutes / hours / date), stability against clock skew (never
/// negative ages)"). Mirrors Android's `RelativeTimeFormatterTest.kt` case-for-case.
@MainActor
struct RelativeTimeFormatterTests {

    @Test func under60Seconds_rendersJustNow() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-26T10:00:45Z") == "Just now")
    }

    @Test func exactlyZeroElapsed_rendersJustNow() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-26T10:00:00Z") == "Just now")
    }

    @Test func twentyFourMinutes_rendersTheSpecsOwnExampleVerbatim() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-26T10:24:00Z") == "24 min ago")
    }

    @Test func oneMinute_rendersSingularSafeAs1MinAgo() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-26T10:01:00Z") == "1 min ago")
    }

    @Test func fiftyNineMinutesFiftyNineSeconds_stillRendersMinutes_notHours() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-26T10:59:59Z") == "59 min ago")
    }

    @Test func exactlyOneHour_crossesIntoTheHoursBucket() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-26T11:00:00Z") == "1 hr ago")
    }

    @Test func twentyThreeHoursFiftyNineMinutes_stillRendersHours_notADate() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-27T09:59:00Z") == "23 hr ago")
    }

    @Test func twentyFourHoursOrMore_rendersACalendarDate_notAHugeHourCount() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:00Z", nowIso: "2026-08-27T10:00:00Z") == "Aug 26")
    }

    @Test func manyDaysOld_stillRendersAsACalendarDate() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-07-19T09:05:12Z", nowIso: "2026-08-26T10:00:00Z") == "Jul 19")
    }

    @Test func clockSkewPlacingRecordedAtSlightlyInTheFuture_neverRendersANegativeAge() {
        #expect(RelativeTimeFormatter.format(recordedAtIso: "2026-08-26T10:00:30Z", nowIso: "2026-08-26T10:00:00Z") == "Just now")
    }
}
