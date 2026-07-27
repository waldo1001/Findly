package com.findly.android.queue.worker

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Enqueues the low-frequency settings-poll worker (specs/009-device-runtime.md §4: "at least
 * every 6 hours") — kept separate from [LocationSyncScheduler] because this one runs
 * **unconditionally**, regardless of pause/interval state: it is the mechanism that *detects*
 * resume, so pausing must never cancel it. `ExistingPeriodicWorkPolicy.KEEP` (not `UPDATE`) since
 * its own cadence never changes — call [ensureScheduled] once, at app start after sign-in.
 */
class SettingsPollScheduler(private val context: Context) {
    fun ensureScheduled() {
        val request = PeriodicWorkRequestBuilder<SettingsPollWorker>(POLL_INTERVAL_HOURS, TimeUnit.HOURS).build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(UNIQUE_WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    private companion object {
        const val UNIQUE_WORK_NAME = "findly-settings-poll"
        const val POLL_INTERVAL_HOURS = 6L
    }
}
