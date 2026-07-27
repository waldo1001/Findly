package com.findly.android.pushmessages

/** Posts an already-built notification title somewhere real. [GeofenceEventNotifier] is the
 * production Android implementation; kept as its own interface so [GeofenceEventPushHandler]
 * stays unit-testable without any `Context`/`NotificationManager`. */
fun interface GeofenceNotifier {
    fun notify(title: String)
}

/**
 * `GEOFENCE_EVENT` (001-api-contract.md §8.2; specs/009-device-runtime.md §5.3) — a user-visible
 * notification about another family member; no location action is taken. All the testable logic
 * (the exact title template) lives in [GeofenceEventNotificationTemplate]; a malformed payload is
 * dropped silently and never reaches [notifier].
 */
class GeofenceEventPushHandler(private val notifier: GeofenceNotifier) {
    fun handle(data: Map<String, String>) {
        val title = GeofenceEventNotificationTemplate.titleFor(data) ?: return
        notifier.notify(title)
    }
}
