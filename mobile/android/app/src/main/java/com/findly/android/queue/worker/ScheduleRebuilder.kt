package com.findly.android.queue.worker

/**
 * Seam invoked whenever `syncIntervalMinutes`/`trackingEnabled` arrive by any of
 * specs/009-device-runtime.md §3.5's three paths — the `SETTINGS_CHANGED` push (§5.2), the §1
 * flush piggyback, or the paused-device poll (§4) — and the on-device schedule needs to be
 * rebuilt. A9 wires this from the push path
 * ([com.findly.android.pushmessages.SettingsChangedPushHandler]); A10 wires `AppContainer`'s
 * implementation straight onto
 * [com.findly.android.location.settings.DeviceSettingsCoordinator.applySettings] — the same entry
 * point the other two §3.5 paths use — so a `SETTINGS_CHANGED` push gets the full §4 pause
 * sequence (stop worker, stop service, unregister geofences) for free, not just a bare schedule
 * call.
 */
fun interface ScheduleRebuilder {
    fun rebuild(syncIntervalMinutes: Int, trackingEnabled: Boolean)
}
