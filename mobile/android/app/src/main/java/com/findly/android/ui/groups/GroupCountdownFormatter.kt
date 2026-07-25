package com.findly.android.ui.groups

import java.time.Duration
import java.time.Instant

/**
 * A compact "time left" label for a group's `endsAt` (specs/003-android-client.md §12.2's
 * `GroupsListScreen` — "a countdown to `endsAt`"). Pure — `now` is an explicit parameter (an ISO
 * 8601 UTC instant, 001-api-contract.md §1.4) so the function is deterministic under test; the one
 * real call site passes `Instant.now().toString()`.
 */
object GroupCountdownFormatter {

    /** Renders the time remaining until [endsAtIso], relative to [nowIso]. `"Ended"` once
     * [nowIso] is at or past [endsAtIso] — this is a display label only, never the authoritative
     * `state` (005 §2.2 owns that; a group can still be `"active"` server-side for a few seconds
     * after this flips to `"Ended"` on-device due to clock granularity, which is harmless — the
     * next `refresh()` reconciles it). */
    fun format(endsAtIso: String, nowIso: String): String {
        val endsAt = Instant.parse(endsAtIso)
        val now = Instant.parse(nowIso)
        val remaining = Duration.between(now, endsAt)
        if (remaining.isZero || remaining.isNegative) return "Ended"

        val days = remaining.toDays()
        val hours = remaining.toHours() % 24
        val minutes = remaining.toMinutes() % 60

        return when {
            days > 0 -> "${days}d ${hours}h left"
            hours > 0 -> "${hours}h ${minutes}m left"
            else -> "${minutes}m left"
        }
    }
}
