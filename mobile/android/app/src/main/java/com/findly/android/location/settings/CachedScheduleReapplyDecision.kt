package com.findly.android.location.settings

import com.findly.android.network.DeviceSettingsSnapshot

/**
 * specs/009-device-runtime.md §3.2 "Restart and recovery" / §3.5: the idempotent "re-apply the
 * cached schedule" decision behind `AppContainer.reapplyCachedSchedule` — the single call site
 * cold start, every foreground, and the boot / package-replaced receiver all go through, rather
 * than three divergent copies of "read cached settings, reschedule if tracking is on".
 *
 * Deliberately narrower than [DeviceSettingsCoordinator]'s pause/resume/geofence handling: this
 * only ever rebuilds the sync schedule from whatever is already cached, and is safe to call as
 * often as those three triggers fire ("WorkManager's `UPDATE` policy and a redundant
 * `startForegroundService` are both no-ops when nothing changed", §3.2).
 */
sealed class CachedScheduleReapplyDecision {
    data class Reschedule(val syncIntervalMinutes: Int) : CachedScheduleReapplyDecision()
    data object DoNothing : CachedScheduleReapplyDecision()

    companion object {
        fun decide(cached: DeviceSettingsSnapshot?): CachedScheduleReapplyDecision {
            if (cached == null || !cached.trackingEnabled) return DoNothing
            return Reschedule(cached.syncIntervalMinutes)
        }
    }
}
