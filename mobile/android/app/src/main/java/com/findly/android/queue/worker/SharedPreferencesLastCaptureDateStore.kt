package com.findly.android.queue.worker

import android.content.Context
import java.time.LocalDate

/** Real, thin Android-framework [LastCaptureDateStore] — untested, like
 * `SharedPreferencesDeviceIdStore` (specs/003-android-client.md §3). */
class SharedPreferencesLastCaptureDateStore(context: Context) : LastCaptureDateStore {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override suspend fun lastCaptureDate(): LocalDate? =
        prefs.getString(KEY_LAST_CAPTURE_DATE, null)?.let { LocalDate.parse(it) }

    override suspend fun recordCaptureDate(date: LocalDate) {
        prefs.edit().putString(KEY_LAST_CAPTURE_DATE, date.toString()).apply()
    }

    private companion object {
        const val PREFS_NAME = "findly_capture_state"
        const val KEY_LAST_CAPTURE_DATE = "last_capture_local_date"
    }
}
