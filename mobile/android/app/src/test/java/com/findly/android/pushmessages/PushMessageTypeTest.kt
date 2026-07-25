package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PushMessageTypeTest {

    @Test
    fun `parses all four catalog types`() {
        assertEquals(PushMessageType.LocateRequest, PushMessageType.from(mapOf("type" to "LOCATE_REQUEST")))
        assertEquals(PushMessageType.GeofenceEvent, PushMessageType.from(mapOf("type" to "GEOFENCE_EVENT")))
        assertEquals(PushMessageType.SettingsChanged, PushMessageType.from(mapOf("type" to "SETTINGS_CHANGED")))
        assertEquals(
            PushMessageType.GeofenceConfigChanged,
            PushMessageType.from(mapOf("type" to "GEOFENCE_CONFIG_CHANGED")),
        )
    }

    @Test
    fun `unknown or missing type yields Unrecognized rather than throwing`() {
        val unknown = PushMessageType.from(mapOf("type" to "SOMETHING_NEW"))
        assertTrue(unknown is PushMessageType.Unrecognized)
        assertEquals("SOMETHING_NEW", (unknown as PushMessageType.Unrecognized).rawType)

        val missing = PushMessageType.from(emptyMap())
        assertTrue(missing is PushMessageType.Unrecognized)
        assertEquals("", (missing as PushMessageType.Unrecognized).rawType)
    }
}
