package com.findly.android.queue.worker

/**
 * Which scheduling mechanism a given `syncIntervalMinutes` uses (specs/009-device-runtime.md §3).
 * `1440` (once/day, §3.3) is still [WorkManager] — a 24-hour `PeriodicWorkRequest` is permitted;
 * what makes it "once per day" rather than "every 24h since last fix" is the worker's own
 * same-local-day skip check, not a different scheduling primitive.
 */
sealed class SyncStrategy {
    data class WorkManager(val intervalMinutes: Int) : SyncStrategy()
    data class ForegroundService(val intervalMinutes: Int) : SyncStrategy()
}

/**
 * Pure interval → strategy selection (specs/009 §3.1/§3.2): WorkManager's periodic floor is
 * 15 minutes, so 5/10-minute targets go to the foreground service instead (§3.1: "WorkManager's
 * floor is 15 minutes; 5/10-minute targets therefore go to §3.2"). Every other allowed value
 * (001-api-contract.md §1.4: `5, 10, 15, 30, 60, 120, 1440`) uses WorkManager.
 */
object SyncStrategySelector {
    private val FOREGROUND_SERVICE_INTERVALS = setOf(5, 10)

    fun strategyFor(syncIntervalMinutes: Int): SyncStrategy =
        if (syncIntervalMinutes in FOREGROUND_SERVICE_INTERVALS) {
            SyncStrategy.ForegroundService(syncIntervalMinutes)
        } else {
            SyncStrategy.WorkManager(syncIntervalMinutes)
        }
}
