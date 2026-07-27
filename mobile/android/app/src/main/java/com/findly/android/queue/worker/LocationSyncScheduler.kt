package com.findly.android.queue.worker

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.findly.android.location.settings.SyncScheduler
import java.time.Duration
import java.util.concurrent.TimeUnit
import androidx.work.BackoffPolicy as WorkManagerBackoffPolicy

/**
 * Real [SyncScheduler] (specs/009-device-runtime.md §3): a single **unique**
 * `findly-location-sync` `PeriodicWorkRequest` for WorkManager-eligible intervals (§3.1: ≥15 min,
 * §3.3: 1440 too — the once-per-day semantics live in [OnceDailyGate] inside
 * [LocationSyncRunner], not in a different scheduling primitive), or the §3.2 foreground service
 * for 5/10-minute intervals via [foregroundServiceController]. [SyncStrategySelector] makes the
 * actual interval→strategy decision (tested in isolation, `SyncStrategySelectorTest`). Thin,
 * untested Android-framework glue by design — mirrors the backend's untested `src/functions`
 * (backend/README.md's hexagonal split).
 *
 * Per A13's note (specs/009 §8): the §3.2 foreground-service notification
 * ([LocationForegroundService]) uses `R.drawable.ic_stat_locating`, not `ic_stat_findly` (which
 * is reserved for the general/geofence-alert notifications).
 */
class LocationSyncScheduler(
    private val context: Context,
    private val foregroundServiceController: ForegroundServiceController,
) : SyncScheduler {

    override fun reschedule(syncIntervalMinutes: Int) {
        when (val strategy = SyncStrategySelector.strategyFor(syncIntervalMinutes)) {
            is SyncStrategy.WorkManager -> {
                foregroundServiceController.stop()
                enqueueWorkManager(strategy.intervalMinutes)
            }
            is SyncStrategy.ForegroundService -> {
                WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
                foregroundServiceController.start(strategy.intervalMinutes)
            }
        }
    }

    override fun cancelAll() {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
        foregroundServiceController.stop()
    }

    private fun enqueueWorkManager(intervalMinutes: Int) {
        // specs/009 §3.1: "flex interval = min(5 min, period/3)" - always exactly 5 in practice
        // (every WorkManager-eligible interval is >= 15, so period/3 is always >= 5), spelled out
        // as the spec's own formula rather than hardcoded so the intent stays obvious.
        val flexMinutes = minOf(5, intervalMinutes / 3)
        val request = PeriodicWorkRequestBuilder<LocationSyncWorker>(
            intervalMinutes.toLong(), TimeUnit.MINUTES,
            flexMinutes.toLong(), TimeUnit.MINUTES,
        )
            // §3.1: "Constraints: none on network - the worker captures a fix and queues it even
            // offline" - deliberately no setConstraints(...) call.
            .setBackoffCriteria(WorkManagerBackoffPolicy.EXPONENTIAL, Duration.ofSeconds(30))
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(UNIQUE_WORK_NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    companion object {
        const val UNIQUE_WORK_NAME = "findly-location-sync"
    }
}
