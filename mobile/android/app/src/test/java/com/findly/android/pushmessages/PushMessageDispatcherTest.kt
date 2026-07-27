package com.findly.android.pushmessages

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.fakes.FakeGeofenceNotifier
import com.findly.android.fakes.FakeGeofenceRegistrar
import com.findly.android.fakes.FakeLocateApi
import com.findly.android.fakes.FakeLocationCapturer
import com.findly.android.fakes.FakeScheduleRebuilder
import com.findly.android.fakes.InMemoryGeofenceConfigStateStore
import com.findly.android.location.settings.GeofenceConfigSyncCoordinator
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5 — routes an FCM data payload to exactly one of the four
 * per-type handlers by `data["type"]` (001-api-contract.md §8), reusing [PushMessageType]'s
 * existing parser; unknown/reserved types (§8.7) run no handler at all. */
class PushMessageDispatcherTest {

    private class Fixture {
        val locationCapturer = FakeLocationCapturer(fixToReturn = null)
        val locateApi = FakeLocateApi()
        val scheduleRebuilder = FakeScheduleRebuilder()
        val geofenceNotifier = FakeGeofenceNotifier()
        val geofenceApi = FakeGeofenceApi()
        val geofenceRegistrar = FakeGeofenceRegistrar()
        val geofenceConfigSyncCoordinator = GeofenceConfigSyncCoordinator(
            geofenceApi,
            InMemoryGeofenceConfigStateStore(),
            geofenceRegistrar,
        )

        val dispatcher = PushMessageDispatcher(
            locateRequestHandler = LocateRequestPushHandler(
                locationCapturer = locationCapturer,
                locateApi = locateApi,
                deviceIdProvider = { "device-1" },
            ),
            settingsChangedHandler = SettingsChangedPushHandler(scheduleRebuilder),
            geofenceEventHandler = GeofenceEventPushHandler(geofenceNotifier),
            geofenceConfigChangedHandler = GeofenceConfigChangedPushHandler(geofenceConfigSyncCoordinator),
        )

        fun assertNothingElseRan(except: String) {
            if (except != "locate") assertTrue(locationCapturer.requestedTiers.isEmpty())
            if (except != "settings") assertTrue(scheduleRebuilder.calls.isEmpty())
            if (except != "geofenceEvent") assertTrue(geofenceNotifier.titles.isEmpty())
            if (except != "geofenceConfig") assertTrue(geofenceApi.getGeofencesCalls.isEmpty())
        }
    }

    @Test
    fun `LOCATE_REQUEST routes only to the locate handler`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(
            // Far-future so this stays within the §5.1 10-minute grace window no matter when the
            // test actually runs (the handler's default `now` is the real system clock).
            mapOf("type" to "LOCATE_REQUEST", "requestId" to "lr_1", "expiresAt" to "2099-01-01T00:00:00Z"),
        )

        assertTrue(f.locationCapturer.requestedTiers.isNotEmpty())
        f.assertNothingElseRan(except = "locate")
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
    fun `GEOFENCE_CONFIG_CHANGED routes only to the config-changed handler`() = runTest {
        val f = Fixture()

        f.dispatcher.dispatch(mapOf("type" to "GEOFENCE_CONFIG_CHANGED", "etag" to "\"9\""))

        assertEquals(1, f.geofenceApi.getGeofencesCalls.size)
        f.assertNothingElseRan(except = "geofenceConfig")
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
