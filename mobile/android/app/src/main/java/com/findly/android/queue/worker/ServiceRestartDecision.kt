package com.findly.android.queue.worker

import com.findly.android.network.DeviceSettingsSnapshot

/**
 * specs/009-device-runtime.md §3.2 "Restart and recovery": what `LocationForegroundService`
 * MUST do when the OS restarts it with a **null** `Intent` (a `START_STICKY` restart carries no
 * extras) — read the cached [DeviceSettingsSnapshot] (the same store §3.5 writes,
 * `SharedPreferencesDeviceSettingsStateStore`) and either resume the loop at the cached interval
 * or `stopSelf()`. Pure so the decision is unit-tested without a `Service`/`Context` in the loop.
 *
 * Deliberately expressed against [SyncStrategySelector] ("is this even a foreground-service
 * interval") rather than a hardcoded threshold like "≥ 60": `SyncStrategySelector` itself stays
 * unchanged by this task (A40) and is the only thing A41 needs to touch to widen the
 * foreground-service range to 5/10/15/30 — this decision then follows automatically, with no
 * change of its own.
 */
sealed class ServiceRestartDecision {
    data class StartWithInterval(val syncIntervalMinutes: Int) : ServiceRestartDecision()
    data object Stop : ServiceRestartDecision()

    companion object {
        fun decide(cached: DeviceSettingsSnapshot?): ServiceRestartDecision {
            if (cached == null || !cached.trackingEnabled) return Stop
            val strategy = SyncStrategySelector.strategyFor(cached.syncIntervalMinutes)
            return if (strategy is SyncStrategy.ForegroundService) {
                StartWithInterval(cached.syncIntervalMinutes)
            } else {
                Stop
            }
        }
    }
}
