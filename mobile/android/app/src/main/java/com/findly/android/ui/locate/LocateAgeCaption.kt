package com.findly.android.ui.locate

import java.time.Duration
import java.time.Instant

/**
 * specs/009-device-runtime.md §5.1 "Requester side": a [LocateOutcome.LATE] position is "rendered
 * exactly like fresh plus an age caption". Pure so [LocateScreen] doesn't need any wall-clock
 * dependency in a test; a malformed `recordedAt` (should never happen — it comes straight off a
 * parsed server response) yields an empty string rather than crashing the screen.
 */
object LocateAgeCaption {
    fun forRecordedAt(recordedAt: String, now: Instant = Instant.now()): String {
        val recorded = try {
            Instant.parse(recordedAt)
        } catch (e: Exception) {
            return ""
        }
        val minutes = Duration.between(recorded, now).toMinutes().coerceAtLeast(0)
        return when (minutes) {
            0L -> "just now"
            1L -> "1 minute ago"
            else -> "$minutes minutes ago"
        }
    }
}
