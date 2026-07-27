package com.findly.android.queue.worker

import java.time.LocalDate

/**
 * 000-overview.md §O3 / specs/009-device-runtime.md §3.3: "at least one fix per device-local
 * calendar day, taken opportunistically" — explicitly **not** "24 h since the last fix" (drift
 * makes that useless). The periodic worker consults this before capturing when its own
 * `syncIntervalMinutes` is the 1440 tier; every other interval is unaffected ([shouldSkipCapture]
 * is always `false` for them; the schedule itself already governs their cadence).
 */
object OnceDailyGate {
    private const val ONCE_PER_DAY_INTERVAL = 1440

    fun shouldSkipCapture(syncIntervalMinutes: Int, today: LocalDate, lastCaptureLocalDate: LocalDate?): Boolean =
        syncIntervalMinutes == ONCE_PER_DAY_INTERVAL && lastCaptureLocalDate == today
}
