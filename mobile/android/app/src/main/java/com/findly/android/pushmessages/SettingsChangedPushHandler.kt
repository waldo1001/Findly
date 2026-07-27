package com.findly.android.pushmessages

import com.findly.android.queue.worker.ScheduleRebuilder

/**
 * `SETTINGS_CHANGED` (001-api-contract.md §8.3; specs/009-device-runtime.md §5.2/§3.5). Always
 * carries the complete current values of both fields — full state, never a delta — so this is
 * applied idempotently and reorder-safe, exactly like the wire contract requires. A malformed or
 * partial payload (missing/non-numeric `syncIntervalMinutes`, missing/non-boolean
 * `trackingEnabled`) is dropped silently rather than applied partially (009 §5 intro).
 */
class SettingsChangedPushHandler(private val scheduleRebuilder: ScheduleRebuilder) {
    fun handle(data: Map<String, String>) {
        val syncIntervalMinutes = data["syncIntervalMinutes"]?.toIntOrNull() ?: return
        val trackingEnabled = data["trackingEnabled"]?.toBooleanStrictOrNull() ?: return
        scheduleRebuilder.rebuild(syncIntervalMinutes, trackingEnabled)
    }
}
