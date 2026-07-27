package com.findly.android.location.settings

import com.findly.android.network.DeviceSettingsSnapshot

/** What [DeviceSettingsCoordinator.applySettings] must do about the pause/resume side of a
 * settings change (specs/009-device-runtime.md §3.5/§4). */
enum class PauseAction {
    NONE,
    PAUSE,
    RESUME,
}

data class SettingsChangeActions(val rebuildSchedule: Boolean, val pauseAction: PauseAction)

/**
 * Pure decision function for specs/009-device-runtime.md §3.5: "on **any** path, if
 * `syncIntervalMinutes` changed the schedule MUST be rebuilt immediately... if `trackingEnabled`
 * changed, apply §4." [previous] is `null` on the very first settings application this process
 * has ever seen (app cold start before any settings have been cached) — treated as "everything
 * changed" so a fresh install/process always ends up with a correctly (re)built schedule.
 */
object SettingsChangeDecision {
    fun decide(previous: DeviceSettingsSnapshot?, next: DeviceSettingsSnapshot): SettingsChangeActions {
        val intervalChanged = previous == null || previous.syncIntervalMinutes != next.syncIntervalMinutes
        val trackingChanged = previous == null || previous.trackingEnabled != next.trackingEnabled

        val pauseAction = when {
            !trackingChanged -> PauseAction.NONE
            !next.trackingEnabled -> PauseAction.PAUSE
            else -> PauseAction.RESUME
        }

        // A paused target has nothing to schedule. An active target rebuilds when the interval
        // itself changed, or when tracking just turned back on (resume must restore the schedule
        // even if the interval didn't change, §4) - either way that's "pauseAction == RESUME".
        val rebuildSchedule = next.trackingEnabled && (intervalChanged || pauseAction == PauseAction.RESUME)

        return SettingsChangeActions(rebuildSchedule, pauseAction)
    }
}
