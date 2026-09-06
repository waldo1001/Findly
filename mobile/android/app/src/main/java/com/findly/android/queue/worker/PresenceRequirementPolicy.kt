package com.findly.android.queue.worker

import com.findly.android.network.DeviceSettingsSnapshot

/**
 * specs/009-device-runtime.md §3.2/§7, 000 §D19: whether presence is *currently* the effective
 * sync strategy for this device. Extracted (code-review fix, A41 round 2 finding 8) from
 * `AppContainer.presenceCurrentlyRequired`, which encoded these same three rules — no cached
 * settings, paused, else the effective strategy — inline and untested, the sole gate on a §3.2
 * MUST ("the client MUST, once per install, explain and offer..."). `AppContainer` now does only
 * the two reads ([DeviceSettingsSnapshot] + the live background-permission check) and delegates
 * the decision here.
 *
 * Deliberately expressed against [EffectiveSyncStrategySelector] (interval **and** permission)
 * rather than [SyncStrategySelector] alone — the same reasoning as [ServiceRestartDecision]'s own
 * doc: a device whose interval would ideally run the foreground service but that lacks
 * `ACCESS_BACKGROUND_LOCATION` is not actually running presence, so it must not be offered the
 * battery exemption either (finding 2's fix makes this the *only* place either caller reads
 * "granted").
 */
object PresenceRequirementPolicy {
    fun decide(cached: DeviceSettingsSnapshot?, backgroundLocationGranted: Boolean): Boolean {
        if (cached == null || !cached.trackingEnabled) return false
        return EffectiveSyncStrategySelector.strategyFor(
            cached.syncIntervalMinutes,
            backgroundLocationGranted,
        ) is SyncStrategy.ForegroundService
    }
}
