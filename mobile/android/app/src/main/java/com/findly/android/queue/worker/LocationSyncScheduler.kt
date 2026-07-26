package com.findly.android.queue.worker

import android.content.Context
import androidx.work.WorkManager

/**
 * Holds the WorkManager periodic-request-building TODO (specs/003-android-client.md §10.5).
 * `syncIntervalMinutes` ∈ {5, 10} additionally needs the persistent-notification foreground
 * service path instead of WorkManager (000-overview.md §O2, specs/003 §11) — neither path is
 * implemented here; both are A2 scope.
 *
 * TODO(A2/A10): for ≥15-minute intervals, build a
 * `PeriodicWorkRequestBuilder<LocationSyncWorker>(syncIntervalMinutes, TimeUnit.MINUTES)` and
 * call `WorkManager.getInstance(context).enqueueUniquePeriodicWork(UNIQUE_WORK_NAME,
 * ExistingPeriodicWorkPolicy.UPDATE, request)`; for 5/10-minute intervals, start the foreground
 * service instead (000 §O2). [cancel] is real (used on pause / sign-out) — the rest is scaffold.
 * Untested Android-framework glue by design.
 *
 * A13 note for whoever builds that foreground service (A10): its persistent notification
 * (specs/009-device-runtime.md §3.2, normative copy "Findly is sharing your location") MUST use
 * `R.drawable.ic_stat_locating` as the small icon, per 009 §8 — not `ic_stat_findly`, which is
 * reserved for the general/geofence-alert notifications.
 */
class LocationSyncScheduler(private val context: Context) {

    fun schedule(syncIntervalMinutes: Int) {
        // TODO(A2): WorkManager.getInstance(context).enqueueUniquePeriodicWork(...) for >=15 min,
        // or start the foreground service for 5/10-min intervals (000 §O2).
    }

    fun cancel() {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }

    private companion object {
        const val UNIQUE_WORK_NAME = "location-sync"
    }
}
