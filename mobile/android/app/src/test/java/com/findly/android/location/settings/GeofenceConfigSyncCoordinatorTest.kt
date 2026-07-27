package com.findly.android.location.settings

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.fakes.FakeGeofenceRegistrar
import com.findly.android.fakes.InMemoryGeofenceConfigStateStore
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.ETagged
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [GeofenceConfigSyncCoordinator] — the consolidated "fetch (If-None-Match) -> update cache ->
 * full re-register" sequence (specs/009-device-runtime.md §6.2) shared by (at least) four of the
 * five registration triggers.
 */
class GeofenceConfigSyncCoordinatorTest {

    private val home = GeofenceDto(
        geofenceId = "gf_home",
        name = "Home",
        lat = 51.05,
        lon = 3.71,
        radiusM = 150.0,
        icon = "home",
        notifyOnEnter = true,
        notifyOnExit = true,
    )
    private val work = GeofenceDto(
        geofenceId = "gf_work",
        name = "Work",
        lat = 51.06,
        lon = 3.72,
        radiusM = 200.0,
        icon = "work",
        notifyOnEnter = true,
        notifyOnExit = false,
    )

    private class Harness(initialCache: CachedGeofenceConfig? = null) {
        val api = FakeGeofenceApi()
        val configStore = InMemoryGeofenceConfigStateStore(initialCache)
        val registrar = FakeGeofenceRegistrar()
        val coordinator = GeofenceConfigSyncCoordinator(api, configStore, registrar)
    }

    @Test
    fun `first sync with no cache fetches unconditionally, caches the result, and registers it`() = runTest {
        val harness = Harness()
        harness.api.getGeofencesResult = ApiResult.Success(
            ETagged(GeofenceConfigResponseDto(version = 1, geofences = listOf(home)), "\"1\""),
            features = defaultFeatures(),
        )

        harness.coordinator.sync()

        assertEquals(listOf<String?>(null), harness.api.getGeofencesCalls)
        assertEquals(CachedGeofenceConfig("\"1\"", listOf(home)), harness.configStore.current())
        assertEquals(listOf(listOf(home) to "\"1\""), harness.registrar.calls)
    }

    @Test
    fun `a fresh fetch passes the cached etag as If-None-Match`() = runTest {
        val harness = Harness(initialCache = CachedGeofenceConfig("\"1\"", listOf(home)))
        harness.api.getGeofencesResult = ApiResult.Success(
            ETagged(GeofenceConfigResponseDto(version = 2, geofences = listOf(home, work)), "\"2\""),
            features = defaultFeatures(),
        )

        harness.coordinator.sync()

        assertEquals(listOf("\"1\""), harness.api.getGeofencesCalls)
        assertEquals(CachedGeofenceConfig("\"2\"", listOf(home, work)), harness.configStore.current())
    }

    @Test
    fun `the geofence list is capped at features_limits_maxGeofences`() = runTest {
        val harness = Harness()
        val many = (1..25).map { home.copy(geofenceId = "gf_$it") }
        harness.api.getGeofencesResult = ApiResult.Success(
            ETagged(GeofenceConfigResponseDto(version = 1, geofences = many), "\"1\""),
            features = defaultFeatures(maxGeofences = 20),
        )

        harness.coordinator.sync()

        val cached = requireNotNull(harness.configStore.current())
        assertEquals(20, cached.geofences.size)
        assertEquals(20, harness.registrar.calls.single().first.size)
    }

    @Test
    fun `a 304 (config unchanged) still re-registers from the cached document`() = runTest {
        val harness = Harness(initialCache = CachedGeofenceConfig("\"1\"", listOf(home)))
        harness.api.getGeofencesResult = ApiResult.Success(null, features = null)

        harness.coordinator.sync()

        assertEquals(listOf(listOf(home) to "\"1\""), harness.registrar.calls)
        // The cache itself is untouched - nothing new to store.
        assertEquals(CachedGeofenceConfig("\"1\"", listOf(home)), harness.configStore.current())
    }

    @Test
    fun `a 304 with nothing ever cached is a silent no-op`() = runTest {
        val harness = Harness(initialCache = null)
        harness.api.getGeofencesResult = ApiResult.Success(null, features = null)

        harness.coordinator.sync()

        assertTrue(harness.registrar.calls.isEmpty())
    }

    @Test
    fun `a failed fetch falls back to registering from the cached document`() = runTest {
        val harness = Harness(initialCache = CachedGeofenceConfig("\"1\"", listOf(home)))
        harness.api.getGeofencesResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))

        harness.coordinator.sync()

        assertEquals(listOf(listOf(home) to "\"1\""), harness.registrar.calls)
    }

    @Test
    fun `a failed fetch with nothing ever cached is a silent no-op`() = runTest {
        val harness = Harness(initialCache = null)
        harness.api.getGeofencesResult = ApiResult.Failure(ApiError.InternalError("boom", null))

        harness.coordinator.sync()

        assertTrue(harness.registrar.calls.isEmpty())
    }

    @Test
    fun `syncIfEtagChanged skips the network call entirely when the observed etag matches the cache`() = runTest {
        val harness = Harness(initialCache = CachedGeofenceConfig("\"1\"", listOf(home)))

        harness.coordinator.syncIfEtagChanged("\"1\"")

        assertTrue(harness.api.getGeofencesCalls.isEmpty())
        assertTrue(harness.registrar.calls.isEmpty())
    }

    @Test
    fun `syncIfEtagChanged triggers a full sync when the observed etag differs from the cache`() = runTest {
        val harness = Harness(initialCache = CachedGeofenceConfig("\"1\"", listOf(home)))
        harness.api.getGeofencesResult = ApiResult.Success(
            ETagged(GeofenceConfigResponseDto(version = 2, geofences = listOf(home, work)), "\"2\""),
            features = defaultFeatures(),
        )

        harness.coordinator.syncIfEtagChanged("\"2\"")

        assertEquals(listOf("\"1\""), harness.api.getGeofencesCalls)
        assertEquals(listOf(listOf(home, work) to "\"2\""), harness.registrar.calls)
    }

    @Test
    fun `syncIfEtagChanged triggers a sync on the very first observation (no cache yet)`() = runTest {
        val harness = Harness(initialCache = null)
        harness.api.getGeofencesResult = ApiResult.Success(
            ETagged(GeofenceConfigResponseDto(version = 1, geofences = emptyList()), "\"0\""),
            features = defaultFeatures(),
        )

        harness.coordinator.syncIfEtagChanged("\"0\"")

        assertEquals(1, harness.api.getGeofencesCalls.size)
        assertNull(harness.api.getGeofencesCalls.single())
    }
}
