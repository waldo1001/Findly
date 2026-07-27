package com.findly.android.pushmessages

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.fakes.FakeGeofenceRegistrar
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.ETagged
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.4; 001-api-contract.md §8.4 — `GET /geofences`, and on a fresh
 * (non-304) body, hand the config off to platform re-registration (§6.2, A11 scope). */
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
    fun `a fresh config is handed to the registrar with its etag`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 2, geofences = listOf(geofence)), "\"2\""),
                features = defaultFeatures(),
            )
        }
        val registrar = FakeGeofenceRegistrar()

        GeofenceConfigChangedPushHandler(api, registrar).handle()

        assertEquals(listOf(listOf(geofence) to "\"2\""), registrar.calls)
    }

    @Test
    fun `a 304 (null body) never reaches the registrar`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(null, features = null)
        }
        val registrar = FakeGeofenceRegistrar()

        GeofenceConfigChangedPushHandler(api, registrar).handle()

        assertTrue(registrar.calls.isEmpty())
    }

    @Test
    fun `a failed fetch is a silent best-effort no-op`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Failure(ApiError.InternalError("boom", null))
        }
        val registrar = FakeGeofenceRegistrar()

        GeofenceConfigChangedPushHandler(api, registrar).handle()

        assertTrue(registrar.calls.isEmpty())
    }
}
