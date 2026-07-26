package com.findly.android.pushmessages

/**
 * Builds the `GEOFENCE_EVENT` notification title (001-api-contract.md §8.2 — normative template,
 * no time text: "the notification's own timestamp conveys the time in the recipient's
 * locale/zone"). Returns `null` on any malformed/missing field (specs/009-device-runtime.md §5
 * intro: a malformed payload is dropped silently, never crashed on) rather than throwing.
 */
object GeofenceEventNotificationTemplate {
    fun titleFor(data: Map<String, String>): String? {
        val displayName = data["displayName"]?.takeIf { it.isNotBlank() } ?: return null
        val geofenceName = data["geofenceName"]?.takeIf { it.isNotBlank() } ?: return null
        val verb = when (data["transition"]) {
            "enter" -> "arrived at"
            "exit" -> "left"
            else -> return null
        }
        return "$displayName $verb $geofenceName"
    }
}
