package com.findly.android.pushmessages

/**
 * The `data.type` discriminator of every FCM data message (001-api-contract.md §8). Parsing lives
 * here, decoupled from `FirebaseMessagingService`, so [PushMessageDispatcher] (A9,
 * specs/009-device-runtime.md §5) has a typed `when` instead of comparing raw strings — and so
 * it's unit-testable without any Firebase SDK or emulator.
 *
 * Notification icon note (009-device-runtime.md §8): any notification raised for [GeofenceEvent]
 * ("a user-visible notification about another member") MUST set its small icon to
 * `R.drawable.ic_stat_findly` — the monochrome status-bar silhouette, never a colored asset,
 * since Android renders status-bar icons as a mask. Wired this way in `GeofenceEventNotifier`.
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
