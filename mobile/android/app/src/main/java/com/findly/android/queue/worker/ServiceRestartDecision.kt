package com.findly.android.queue.worker

import com.findly.android.network.DeviceSettingsSnapshot

/**
 * specs/009-device-runtime.md §3.2 "Restart and recovery": what `LocationForegroundService`
 * MUST do when the OS restarts it with a **null** `Intent` (a `START_STICKY` restart carries no
 * extras) — read the cached [DeviceSettingsSnapshot] (the same store §3.5 writes,
 * `SharedPreferencesDeviceSettingsStateStore`) and either resume the loop at the cached interval
 * or `stopSelf()`. Pure so the decision is unit-tested without a `Service`/`Context` in the loop.
 *
 * Code-review fix (A41 round 2, finding 1): originally expressed only against
 * [SyncStrategySelector] ("is this even a foreground-service interval"), which never considered
 * `ACCESS_BACKGROUND_LOCATION`. That let a `START_STICKY` restart re-establish the foreground
 * presence service (with the "Findly is sharing your location" notification) after the OS killed
 * the process for a permission revocation from system settings — the platform then denies it
 * location for the life of that restart, violating both §3.2 ("started only when... **and**
 * `ACCESS_BACKGROUND_LOCATION` is granted") and §1.3 ("Presence MUST stop immediately on...
 * permission revocation"). Now expressed against [EffectiveSyncStrategySelector], the exact same
 * permission-aware selector the *forward* path ([com.findly.android.queue.worker.LocationSyncScheduler
 * .reschedule]) already used — `LocationForegroundService` passes it a fresh
 * `backgroundLocationGranted` read (`AppContainer.backgroundLocationGranted()`) on every restart,
 * so the two paths can never drift on what "presence is viable" means.
 */
sealed class ServiceRestartDecision {
    data class StartWithInterval(val syncIntervalMinutes: Int) : ServiceRestartDecision()
    data object Stop : ServiceRestartDecision()

    companion object {
        fun decide(cached: DeviceSettingsSnapshot?, backgroundLocationGranted: Boolean): ServiceRestartDecision {
            if (cached == null || !cached.trackingEnabled) return Stop
            val strategy = EffectiveSyncStrategySelector.strategyFor(
                cached.syncIntervalMinutes,
                backgroundLocationGranted,
            )
            return if (strategy is SyncStrategy.ForegroundService) {
                StartWithInterval(cached.syncIntervalMinutes)
            } else {
                Stop
            }
        }
    }
}
