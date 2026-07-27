package com.findly.android.pushmessages

import com.findly.android.fakes.FakeGeofenceNotifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.3; 001-api-contract.md §8.2 — no location action is taken, only
 * a locally re-rendered alert. */
class GeofenceEventPushHandlerTest {

    @Test
    fun `well-formed payload posts the templated title`() {
        val notifier = FakeGeofenceNotifier()

        GeofenceEventPushHandler(notifier).handle(
            mapOf("displayName" to "Noor", "geofenceName" to "Home", "transition" to "enter"),
        )

        assertEquals(listOf("Noor arrived at Home"), notifier.titles)
    }

    @Test
    fun `exit transition posts the left template`() {
        val notifier = FakeGeofenceNotifier()

        GeofenceEventPushHandler(notifier).handle(
            mapOf("displayName" to "Eric", "geofenceName" to "Work", "transition" to "exit"),
        )

        assertEquals(listOf("Eric left Work"), notifier.titles)
    }

    @Test
    fun `malformed payload never reaches the notifier`() {
        val notifier = FakeGeofenceNotifier()

        GeofenceEventPushHandler(notifier).handle(mapOf("displayName" to "Noor"))

        assertTrue(notifier.titles.isEmpty())
    }
}
