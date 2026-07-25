package com.findly.android.pushmessages

/**
 * The `data.type` discriminator of every FCM data message (001-api-contract.md §8). Parsing
 * lives here, decoupled from any real `FirebaseMessagingService`, so a future
 * `onMessageReceived` override (A2/H1) has a typed `when` instead of comparing raw strings —
 * and so it's unit-testable without any Firebase SDK or emulator.
 */
sealed class PushMessageType {
    data object LocateRequest : PushMessageType()
    data object GeofenceEvent : PushMessageType()
    data object SettingsChanged : PushMessageType()
    data object GeofenceConfigChanged : PushMessageType()
    data class Unrecognized(val rawType: String) : PushMessageType()

    companion object {
        /**
         * [data] is the raw FCM data payload map (all string values, per 001 §8: "all `data`
         * values are strings — clients parse"). A missing or unrecognized `type` yields
         * [Unrecognized] rather than throwing — forward-compatible with future message types.
         */
        fun from(data: Map<String, String>): PushMessageType = when (data["type"]) {
            "LOCATE_REQUEST" -> LocateRequest
            "GEOFENCE_EVENT" -> GeofenceEvent
            "SETTINGS_CHANGED" -> SettingsChanged
            "GEOFENCE_CONFIG_CHANGED" -> GeofenceConfigChanged
            else -> Unrecognized(data["type"].orEmpty())
        }
    }
}
