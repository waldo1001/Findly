package com.findly.android.queue.worker

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.findly.android.location.LocationPermissionState
import com.findly.android.location.settings.SyncScheduler
import java.time.Duration
import java.util.concurrent.TimeUnit
import androidx.work.BackoffPolicy as WorkManagerBackoffPolicy

/**
 * Real [SyncScheduler] (specs/009-device-runtime.md §3): a single **unique**
 * `findly-location-sync` `PeriodicWorkRequest` for WorkManager-eligible intervals (§3.1: ≥15 min,
 * §3.3: 1440 too — the once-per-day semantics live in [OnceDailyGate] inside
 * [LocationSyncRunner], not in a different scheduling primitive), or the §3.2 foreground presence
 * service for 5/10/15/30-minute intervals via [foregroundServiceController]. [EffectiveSyncStrategySelector]
 * makes the actual interval + permission → strategy decision (tested in isolation,
 * `EffectiveSyncStrategySelectorTest`) — [backgroundLocationPermission] supplies its fresh
 * `ACCESS_BACKGROUND_LOCATION` read (§3.2: "started only when... `ACCESS_BACKGROUND_LOCATION` is
 * granted... [otherwise] falls back to §3.1 WorkManager"). Thin, untested Android-framework glue
 * by design — mirrors the backend's untested `src/functions` (backend/README.md's hexagonal
 * split).
 *
 * Per A13's note (specs/009 §8): the §3.2 foreground-service notification
 * ([LocationForegroundService]) uses `R.drawable.ic_stat_locating`, not `ic_stat_findly` (which
 * is reserved for the general/geofence-alert notifications).
 */
class LocationSyncScheduler(
    private val context: Context,
    private val foregroundServiceController: ForegroundServiceController,
    private val backgroundLocationPermission: LocationPermissionState,
) : SyncScheduler {

    override suspend fun reschedule(syncIntervalMinutes: Int) {
        val strategy = EffectiveSyncStrategySelector.strategyFor(
            syncIntervalMinutes,
            backgroundLocationGranted = backgroundLocationPermission.isGranted(),
        )
        when (strategy) {
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
        // Code-review fix (A41 round 2, finding 6): this comment used to claim "every
        // WorkManager-eligible interval is >= 15, so period/3 is always >= 5" - true when this
        // class only ever saw 15/30/60/120/1440, but false as of this branch: the §3.2
        // permission-fallback rule (EffectiveSyncStrategySelector) now routes 5 and 10 into this
        // same method whenever ACCESS_BACKGROUND_LOCATION isn't granted. WorkManager's own
        // PeriodicWorkRequest floor silently clamps a sub-15-minute period up to 15 minutes (and
        // its flex up to 5) - the formula below still computes 1-3 for a 5/10-minute request, but
        // the request that actually reaches the OS runs at the clamped 15/5. specs/009 §3.2 calls
        // this fallback "still opportunistic", so the clamp is the accepted degradation, not a bug
        // - spelled out here so the silent clamp isn't mistaken for one.
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
