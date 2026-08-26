package com.findly.android.ui.map

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §3.1: roster subtitles render humanized relative times
 * ("24 min ago") instead of raw ISO strings, recomputed on a 30 s ticker (never per frame) — the
 * ticker itself is UI plumbing (`MapScreen`), but the formula it calls is pure, shared logic, unit
 * tested here with no Compose/Android dependency (§10's test checklist: "thresholds ('just now' /
 * minutes / hours / date), stability against clock skew (never negative ages)").
 */
class RelativeTimeFormatterTest {

    @Test
    fun `under 60 seconds renders Just now`() {
        assertEquals(
            "Just now",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-26T10:00:45Z"),
        )
    }

    @Test
    fun `exactly zero elapsed renders Just now`() {
        assertEquals(
            "Just now",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-26T10:00:00Z"),
        )
    }

    @Test
    fun `24 minutes renders the spec's own example verbatim`() {
        assertEquals(
            "24 min ago",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-26T10:24:00Z"),
        )
    }

    @Test
    fun `one minute renders singular-safe as 1 min ago`() {
        assertEquals(
            "1 min ago",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-26T10:01:00Z"),
        )
    }

    @Test
    fun `59 minutes 59 seconds still renders minutes, not hours`() {
        assertEquals(
            "59 min ago",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-26T10:59:59Z"),
        )
    }

    @Test
    fun `exactly one hour crosses into the hours bucket`() {
        assertEquals(
            "1 hr ago",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-26T11:00:00Z"),
        )
    }

    @Test
    fun `23 hours 59 minutes still renders hours, not a date`() {
        assertEquals(
            "23 hr ago",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-27T09:59:00Z"),
        )
    }

    @Test
    fun `24 hours or more renders a calendar date, not a huge hour count`() {
        assertEquals(
            "Aug 26",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:00Z", nowIso = "2026-08-27T10:00:00Z"),
        )
    }

    @Test
    fun `many days old still renders as a calendar date`() {
        assertEquals(
            "Jul 19",
            RelativeTimeFormatter.format(recordedAtIso = "2026-07-19T09:05:12Z", nowIso = "2026-08-26T10:00:00Z"),
        )
    }

    @Test
    fun `clock skew placing recordedAt slightly in the future never renders a negative age`() {
        assertEquals(
            "Just now",
            RelativeTimeFormatter.format(recordedAtIso = "2026-08-26T10:00:30Z", nowIso = "2026-08-26T10:00:00Z"),
        )
    }
}
