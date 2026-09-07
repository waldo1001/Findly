package com.findly.android.pushmessages

/**
 * The three routes `FindlyMessagingService.onMessageReceived` can take for one FCM push
 * (specs/009-device-runtime.md §5, A47).
 */
sealed class PushMessageLane {
    /** LOCATE_REQUEST (specs/009 §5.1) — `LocateRequestHandoff.handle`. Never
     * [com.findly.android.pushmessages.PushMessageDispatcher.dispatch]: that is a `suspend fun`
     * the FCM callback would have to `runBlocking` on, exactly what §5.1's "return immediately
     * after handing off" forbids. */
    data object LocateHandoff : PushMessageLane()

    /** GEOFENCE_CONFIG_CHANGED (specs/009 §5.4/§6.2) — the expedited `WorkManager` enqueue
     * directly. Unlike `LOCATE_REQUEST` there is no priority/permission/presence decision to make
     * first, so a synchronous, immediately-returning enqueue call is the whole handoff. */
    data object ExpeditedGeofenceConfigSync : PushMessageLane()

    /** Everything else — `SETTINGS_CHANGED`, `GEOFENCE_EVENT`, an unknown or reserved-future type,
     * and a missing type — routes through [com.findly.android.pushmessages.PushMessageDispatcher].
     * Each of these is cheap in-memory work (a schedule rebuild, posting a local notification, or
     * a no-op for an unrecognized type) with no I/O, so dispatching from inside the FCM callback is
     * safe. */
    data object Dispatcher : PushMessageLane()
}

/**
 * The pure decision behind [PushMessageLane] — `FindlyMessagingService` carries out whichever lane
 * this returns, but never decides it inline (A47, extracted in the same shape as
 * [LocateHandoffPolicy]). This is the one genuinely decidable thing left in
 * `onMessageReceived`'s former `if`/`if`/`runBlocking` chain: *which lane does this push type
 * take*, now unit-tested exhaustively instead of only being pinned indirectly by
 * [com.findly.android.pushmessages.PushMessageDispatcher]'s own tests.
 */
object PushMessageLanePolicy {
    fun decide(type: PushMessageType): PushMessageLane = when (type) {
        is PushMessageType.LocateRequest -> PushMessageLane.LocateHandoff
        is PushMessageType.GeofenceConfigChanged -> PushMessageLane.ExpeditedGeofenceConfigSync
        is PushMessageType.SettingsChanged,
        is PushMessageType.GeofenceEvent,
        is PushMessageType.Unrecognized,
        -> PushMessageLane.Dispatcher
    }
}
