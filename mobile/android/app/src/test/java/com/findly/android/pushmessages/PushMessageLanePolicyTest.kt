package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §5, A47 — the lane decision `FindlyMessagingService.onMessageReceived`
 * makes for every FCM push type, extracted into a pure policy (same shape as [LocateHandoffPolicy])
 * so "which lane does this type take" is unit-tested independently of that class's untestable
 * Android framework surface. LOCATE_REQUEST and GEOFENCE_CONFIG_CHANGED each take their own route —
 * never [PushMessageDispatcher.dispatch], which is a `suspend fun` the caller would have to
 * `runBlocking` on inside the ~10s FCM callback budget (specs/009 §5.1, §5.4) — while every other
 * type, including unknown, reserved-future, and a missing type, routes through the dispatcher. */
class PushMessageLanePolicyTest {

    @Test
    fun `LOCATE_REQUEST takes the locate handoff lane`() {
        assertEquals(
            PushMessageLane.LocateHandoff,
            PushMessageLanePolicy.decide(PushMessageType.LocateRequest),
        )
    }

    @Test
    fun `GEOFENCE_CONFIG_CHANGED takes the expedited work-enqueue lane`() {
        assertEquals(
            PushMessageLane.ExpeditedGeofenceConfigSync,
            PushMessageLanePolicy.decide(PushMessageType.GeofenceConfigChanged),
        )
    }

    @Test
    fun `SETTINGS_CHANGED takes the dispatcher lane`() {
        assertEquals(
            PushMessageLane.Dispatcher,
            PushMessageLanePolicy.decide(PushMessageType.SettingsChanged),
        )
    }

    @Test
    fun `GEOFENCE_EVENT takes the dispatcher lane`() {
        assertEquals(
            PushMessageLane.Dispatcher,
            PushMessageLanePolicy.decide(PushMessageType.GeofenceEvent),
        )
    }

    @Test
    fun `an unknown type takes the dispatcher lane`() {
        val type = PushMessageType.from(mapOf("type" to "GROUP_MEMBER_JOINED"))

        assertEquals(PushMessageLane.Dispatcher, PushMessageLanePolicy.decide(type))
    }

    @Test
    fun `a reserved future type takes the dispatcher lane`() {
        val type = PushMessageType.from(mapOf("type" to "GROUP_ENDING_SOON"))

        assertEquals(PushMessageLane.Dispatcher, PushMessageLanePolicy.decide(type))
    }

    @Test
    fun `a missing type takes the dispatcher lane`() {
        val type = PushMessageType.from(emptyMap())

        assertEquals(PushMessageLane.Dispatcher, PushMessageLanePolicy.decide(type))
    }
}
