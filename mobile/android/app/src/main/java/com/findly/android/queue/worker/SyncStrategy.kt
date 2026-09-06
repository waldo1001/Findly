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
 * Pure interval → strategy selection (specs/009 §3 "Strategy selection", amended 2026-09-06 —
 * 000 §D19): the §1.3 low-power presence mechanism now covers every "live" interval — 5, 10, 15
 * and 30 minutes — not just 5/10 (WorkManager's periodic floor is 15 minutes, which is why 5/10
 * originally needed the foreground service; the D19 presence decision widened the range to all
 * four intervals ≤ 30 for cadence *and* to keep the process alive for `LOCATE_REQUEST`, not just
 * to beat WorkManager's floor). The three "battery saver" values — 60, 120, 1440
 * (001-api-contract.md §1.4) — stay on WorkManager (§3.1/§3.3).
 *
 * This selector answers only "which mechanism is the *ideal* one for this interval" — it does not
 * know about `ACCESS_BACKGROUND_LOCATION`. [EffectiveSyncStrategySelector] layers the §3.2
 * permission-fallback rule on top of this, so [com.findly.android.queue.worker.ServiceRestartDecision]
 * (and any other caller that only ever runs once presence is already known to be viable) can keep
 * depending on this selector alone, unchanged.
 */
object SyncStrategySelector {
    private val FOREGROUND_SERVICE_INTERVALS = setOf(5, 10, 15, 30)

    fun strategyFor(syncIntervalMinutes: Int): SyncStrategy =
        if (syncIntervalMinutes in FOREGROUND_SERVICE_INTERVALS) {
            SyncStrategy.ForegroundService(syncIntervalMinutes)
        } else {
            SyncStrategy.WorkManager(syncIntervalMinutes)
        }
}

/**
 * specs/009-device-runtime.md §3.2: "It MUST be started only when `syncIntervalMinutes` ∈
 * {5, 10, 15, 30} **and** `ACCESS_BACKGROUND_LOCATION` is granted... Without background
 * permission the device falls back to §3.1 WorkManager for its interval (still opportunistic)."
 *
 * Pure layer on top of [SyncStrategySelector]: when the ideal strategy is the foreground presence
 * service but background-location permission is not granted, downgrade to WorkManager at the same
 * interval rather than starting a service that cannot read location in the background (Android
 * 11+ denies location to an FGS started from the background without that permission). A
 * WorkManager-eligible interval (60/120/1440) is unaffected either way — permission plays no part
 * in its selection.
 */
object EffectiveSyncStrategySelector {
    fun strategyFor(syncIntervalMinutes: Int, backgroundLocationGranted: Boolean): SyncStrategy {
        val ideal = SyncStrategySelector.strategyFor(syncIntervalMinutes)
        return if (ideal is SyncStrategy.ForegroundService && !backgroundLocationGranted) {
            SyncStrategy.WorkManager(syncIntervalMinutes)
        } else {
            ideal
        }
    }
}
