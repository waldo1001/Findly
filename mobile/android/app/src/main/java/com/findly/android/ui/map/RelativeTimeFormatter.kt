package com.findly.android.ui.map

import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * specs/010-app-shell-and-screen-ux.md §3.1/§10: pure, shared-logic humanization of a roster row's
 * `recordedAt` (001-api-contract.md §1.4, ISO 8601 UTC) — replaces the raw ISO strings both
 * platforms show today. `nowIso` is an explicit parameter (mirrors [GroupCountdownFormatter]'s
 * `now`-as-parameter shape) so the ticker that recomputes this every 30 s (`MapScreen`) can drive
 * it deterministically and so this stays unit-testable with no clock/Android dependency.
 */
object RelativeTimeFormatter {
    private val DATE_FORMAT = DateTimeFormatter.ofPattern("MMM d", Locale.US).withZone(ZoneOffset.UTC)

    /** "Just now" (< 60 s) / "N min ago" (< 60 min) / "N hr ago" (< 24 h) / a calendar date
     * otherwise (§10: "thresholds ('just now' / minutes / hours / date)"). [recordedAtIso] in the
     * future relative to [nowIso] (clock skew) clamps to "Just now" rather than a negative age
     * (§10: "stability against clock skew (never negative ages)"). */
    fun format(recordedAtIso: String, nowIso: String): String {
        val recordedAt = Instant.parse(recordedAtIso)
        val now = Instant.parse(nowIso)
        val elapsedSeconds = Duration.between(recordedAt, now).seconds.coerceAtLeast(0)

        return when {
            elapsedSeconds < 60 -> "Just now"
            elapsedSeconds < 3_600 -> "${elapsedSeconds / 60} min ago"
            elapsedSeconds < 86_400 -> "${elapsedSeconds / 3_600} hr ago"
            else -> DATE_FORMAT.format(recordedAt)
        }
    }
}
