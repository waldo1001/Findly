package com.findly.android.pushmessages

import com.findly.android.fakes.FakeGeofenceNotifier
import com.findly.android.fakes.FakeScheduleRebuilder
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5 — routes an FCM data payload to exactly one of its two
 * per-type handlers by `data["type"]` (001-api-contract.md §8), reusing [PushMessageType]'s
 * existing parser. `LOCATE_REQUEST` and `GEOFENCE_CONFIG_CHANGED` are never routed here (A47 —
 * [PushMessageLanePolicy] sends both down their own lane before `FindlyMessagingService` ever
 * calls [PushMessageDispatcher.dispatch] — see that class's doc); unknown/reserved types (§8.7)
 * and a missing type also run no handler at all. */
class PushMessageDispatcherTest {

    private class Fixture {
        val scheduleRebuilder = FakeScheduleRebuilder()
        val geofenceNotifier = FakeGeofenceNotifier()

        val dispatcher = PushMessageDispatcher(
            settingsChangedHandler = SettingsChangedPushHandler(scheduleRebuilder),
            geofenceEventHandler = GeofenceEventPushHandler(geofenceNotifier),
        )

        fun assertNothingElseRan(except: String) {
            if (except != "settings") assertTrue(scheduleRebuilder.calls.isEmpty())
            if (except != "geofenceEvent") assertTrue(geofenceNotifier.titles.isEmpty())
        }
    }

    @Test
    fun `SETTINGS_CHANGED routes only to the settings handler`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(
            mapOf("type" to "SETTINGS_CHANGED", "syncIntervalMinutes" to "30", "trackingEnabled" to "false"),
        )

        assertEquals(listOf(30 to false), f.scheduleRebuilder.calls)
        f.assertNothingElseRan(except = "settings")
    }

    @Test
    fun `GEOFENCE_EVENT routes only to the geofence-event handler`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(
            mapOf(
                "type" to "GEOFENCE_EVENT",
                "displayName" to "Noor",
                "geofenceName" to "Home",
                "transition" to "enter",
            ),
        )

        assertEquals(listOf("Noor arrived at Home"), f.geofenceNotifier.titles)
        f.assertNothingElseRan(except = "geofenceEvent")
    }

    @Test
    fun `an unknown type runs no handler at all`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(mapOf("type" to "GROUP_MEMBER_JOINED"))

        f.assertNothingElseRan(except = "none")
    }

    @Test
    fun `a reserved future type runs no handler at all`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(mapOf("type" to "GROUP_ENDING_SOON"))

        f.assertNothingElseRan(except = "none")
    }

    @Test
    fun `a missing type runs no handler at all`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(emptyMap())

        f.assertNothingElseRan(except = "none")
    }
}
