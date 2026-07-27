package com.findly.android.location.settings

import com.findly.android.network.DeviceSettingsSnapshot

/**
 * **The single settings-application entry point** (specs/009-device-runtime.md §3.5) — call
 * [applySettings] from **any** of the three arrival paths whenever a [DeviceSettingsSnapshot] is
 * observed:
 *
 * 1. The `SETTINGS_CHANGED` push (§5.2) — **this is the seam A9's push handler calls.**
 * 2. The `POST /locations` piggyback (001-api-contract.md §5.1's `deviceSettings` field on every
 *    response) — the periodic worker/foreground service/`LocationSyncCoordinator` caller maps
 *    the response DTO to a [DeviceSettingsSnapshot] and calls this after every flush.
 * 3. The paused-device poll (§4, [SettingsPoller]).
 *
 * Idempotent and reorder-safe: applying the same settings twice, or an older snapshot after a
 * newer one already landed, is always evaluated against whatever is currently cached in
 * [stateStore] — never assumed to be a delta (§5.2: "apply both, idempotently... never treat it
 * as a delta").
 *
 * Pause (§4) is implemented here directly rather than through a separate controller: cancelling
 * the schedule and unregistering geofences are the only two actions 009 §4 lists beyond "stop
 * capturing", and "stop capturing" is already a natural consequence of [stateStore] being the
 * same source of truth a real `TrackingPauseState` reads (specs/009 §1.2) — no separate signal is
 * needed. Resume (§4) restores the schedule via the same [rebuildSchedule][SettingsChangeActions]
 * path an interval change uses, and calls [onResume] — `AppContainer` wires this to
 * `GeofenceConfigSyncCoordinator.sync` (specs/009 §6.2: "resume from pause" is one of the five
 * geofence re-registration triggers). Kept as a thin functional seam (like [ScheduleRebuilder]
 * elsewhere) rather than an import of the concrete coordinator, so this class stays decoupled from
 * geofencing's own dependency graph — it only needs to know "call this on resume".
 */
class DeviceSettingsCoordinator(
    private val scheduler: SyncScheduler,
    private val geofenceRegistry: GeofenceRegistry,
    private val stateStore: DeviceSettingsStateStore,
    private val onResume: suspend () -> Unit = {},
) {
    suspend fun applySettings(next: DeviceSettingsSnapshot) {
        val previous = stateStore.current()
        val actions = SettingsChangeDecision.decide(previous, next)

        // Order matters: cache the new settings BEFORE touching the schedule/geofences, so any
        // capture that races this call already observes the new paused state (§1.2's "stop
        // capturing" is enforced by every capture attempt reading stateStore fresh).
        stateStore.update(next)

        when (actions.pauseAction) {
            PauseAction.PAUSE -> {
                scheduler.cancelAll()
                geofenceRegistry.unregisterAll()
            }
            PauseAction.RESUME -> onResume()
            PauseAction.NONE -> Unit
        }

        if (actions.rebuildSchedule) {
            scheduler.reschedule(next.syncIntervalMinutes)
        }
    }
}
