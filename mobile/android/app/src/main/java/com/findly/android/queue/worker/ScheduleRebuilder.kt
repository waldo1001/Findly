package com.findly.android.queue.worker

/**
 * Seam invoked whenever `syncIntervalMinutes`/`trackingEnabled` arrive by any of
 * specs/009-device-runtime.md §3.5's three paths — the `SETTINGS_CHANGED` push (§5.2), the §1
 * flush piggyback, or the paused-device poll (§4) — and the on-device schedule needs to be
 * rebuilt. A9 wires this from the push path only
 * ([com.findly.android.pushmessages.SettingsChangedPushHandler]); the other two paths, and the
 * real WorkManager/foreground-service rebuild + full §4 pause sequence (stop worker, stop
 * service, unregister geofences), are A10/A11 scope. `AppContainer` wires today's implementation
 * straight onto the existing [LocationSyncScheduler] scaffold, whose own `schedule()` is still a
 * no-op TODO(A2) — see that class's doc.
 */
fun interface ScheduleRebuilder {
    fun rebuild(syncIntervalMinutes: Int, trackingEnabled: Boolean)
}
