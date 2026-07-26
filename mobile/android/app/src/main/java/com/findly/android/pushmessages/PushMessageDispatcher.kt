package com.findly.android.pushmessages

/**
 * Routes one FCM data payload to its 001-api-contract.md §8 handler by `data["type"]`
 * (specs/009-device-runtime.md §5), reusing [PushMessageType]'s existing parser rather than a
 * second string comparison. Unknown types and the §8.7 reserved group types both parse to
 * [PushMessageType.Unrecognized] and run no handler at all — 001 §1.1's forward-compatibility
 * rule.
 */
class PushMessageDispatcher(
    private val locateRequestHandler: LocateRequestPushHandler,
    private val settingsChangedHandler: SettingsChangedPushHandler,
    private val geofenceEventHandler: GeofenceEventPushHandler,
    private val geofenceConfigChangedHandler: GeofenceConfigChangedPushHandler,
) {
    suspend fun dispatch(data: Map<String, String>) {
        when (PushMessageType.from(data)) {
            is PushMessageType.LocateRequest -> locateRequestHandler.handle(data)
            is PushMessageType.SettingsChanged -> settingsChangedHandler.handle(data)
            is PushMessageType.GeofenceEvent -> geofenceEventHandler.handle(data)
            is PushMessageType.GeofenceConfigChanged -> geofenceConfigChangedHandler.handle()
            is PushMessageType.Unrecognized -> Unit
        }
    }
}
