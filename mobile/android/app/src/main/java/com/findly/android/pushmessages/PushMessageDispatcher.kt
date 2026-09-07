package com.findly.android.pushmessages

/**
 * Routes one FCM data payload to its 001-api-contract.md §8 handler by `data["type"]`
 * (specs/009-device-runtime.md §5), reusing [PushMessageType]'s existing parser rather than a
 * second string comparison. Unknown types and the §8.7 reserved group types both parse to
 * [PushMessageType.Unrecognized] and run no handler at all — 001 §1.1's forward-compatibility
 * rule.
 *
 * **A47 — `LOCATE_REQUEST` and `GEOFENCE_CONFIG_CHANGED` are never routed here.**
 * [PushMessageLanePolicy] sends both types down their own lane before `FindlyMessagingService`
 * ever calls [dispatch] (see that class's doc) — `dispatch(` has exactly one production call
 * site, and it is reached only for [PushMessageLane.Dispatcher]. This class used to carry a
 * `locateRequestHandler`/`geofenceConfigChangedHandler` pair and a matching `when` branch for
 * each, both unreachable in production; a test asserting either branch "routes correctly" was
 * pinning, as correct, exactly the blocking-I/O-in-the-FCM-callback behaviour A39/A43 existed to
 * remove. Deleted rather than kept "for forward compatibility": no second caller ever existed to
 * justify them, so they were a trap, not a feature. If a genuine second caller of `dispatch`
 * appears later, add the type back deliberately, with its own routing test, at that point — do
 * not restore this by copying the deleted branches back.
 */
class PushMessageDispatcher(
    private val settingsChangedHandler: SettingsChangedPushHandler,
    private val geofenceEventHandler: GeofenceEventPushHandler,
) {
    suspend fun dispatch(data: Map<String, String>) {
        when (PushMessageType.from(data)) {
            is PushMessageType.SettingsChanged -> settingsChangedHandler.handle(data)
            is PushMessageType.GeofenceEvent -> geofenceEventHandler.handle(data)
            is PushMessageType.LocateRequest,
            is PushMessageType.GeofenceConfigChanged,
            is PushMessageType.Unrecognized,
            -> Unit
        }
    }
}
