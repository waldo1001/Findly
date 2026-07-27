package com.findly.android.pushmessages

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.fakes.FakeGeofenceRegistrar
import com.findly.android.fakes.InMemoryGeofenceConfigStateStore
import com.findly.android.fakes.defaultFeatures
import com.findly.android.location.settings.GeofenceConfigSyncCoordinator
import com.findly.android.network.ApiResult
import com.findly.android.network.ETagged
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.4; 001-api-contract.md §8.4 — a thin delegate onto
 * [GeofenceConfigSyncCoordinator.sync] (§6.2); the substantive fetch/cache/cap/304/failure
 * behavior is covered by `GeofenceConfigSyncCoordinatorTest`. */
class GeofenceConfigChangedPushHandlerTest {

    private val geofence = GeofenceDto(
        geofenceId = "gf_home",
        name = "Home",
        lat = 51.05,
        lon = 3.71,
        radiusM = 150.0,
        icon = "home",
        notifyOnEnter = true,
        notifyOnExit = true,
    )

    @Test
    fun `delegates to the coordinator - a fresh config reaches the registrar`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 2, geofences = listOf(geofence)), "\"2\""),
                features = defaultFeatures(),
            )
        }
        val registrar = FakeGeofenceRegistrar()
        val coordinator = GeofenceConfigSyncCoordinator(api, InMemoryGeofenceConfigStateStore(), registrar)

        GeofenceConfigChangedPushHandler(coordinator).handle()

        assertEquals(listOf(listOf(geofence) to "\"2\""), registrar.calls)
    }

    @Test
    fun `delegates to the coordinator - a 304 with nothing cached never reaches the registrar`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(null, features = null)
        }
        val registrar = FakeGeofenceRegistrar()
        val coordinator = GeofenceConfigSyncCoordinator(api, InMemoryGeofenceConfigStateStore(), registrar)

        GeofenceConfigChangedPushHandler(coordinator).handle()

        assertTrue(registrar.calls.isEmpty())
    }
}
