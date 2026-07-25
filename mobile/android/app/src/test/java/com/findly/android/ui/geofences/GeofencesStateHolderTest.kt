package com.findly.android.ui.geofences

import com.findly.android.fakes.FakeGeofenceApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.ETagged
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GeofencesStateHolder] is pure Kotlin — tested with [FakeGeofenceApi]
 * (specs/003-android-client.md §14, §16: "ETag-conflict for geofences"). */
class GeofencesStateHolderTest {

    private val homeDto = GeofenceDto("gf_home", "Home", 51.0543, 3.7174, 150.0, "home", true, true)

    @Test
    fun `load populates geofences and etag`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 4, geofences = listOf(homeDto)), "\"4\""),
                features = defaultFeatures(),
            )
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is GeofencesUiState.Content)
        state as GeofencesUiState.Content
        assertEquals("\"4\"", state.etag)
        assertEquals("Home", state.geofences.single().name)
    }

    @Test
    fun `load failure surfaces Error`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1"))
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is GeofencesUiState.Error)
    }

    @Test
    fun `validate rejects a blank name, an over-length name, and an out-of-range radius`() = runTest {
        val holder = GeofencesStateHolder(FakeGeofenceApi(), backgroundScope)

        assertTrue(holder.validate(draft(name = "")) != null)
        assertTrue(holder.validate(draft(name = "x".repeat(51))) != null)
        assertTrue(holder.validate(draft(radiusM = 99.0)) != null)
        assertTrue(holder.validate(draft(radiusM = 5001.0)) != null)
        assertNull(holder.validate(draft(name = "Home", radiusM = 150.0)))
    }

    @Test
    fun `upsertGeofence adds a new entry and updates an existing one by id`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 1, geofences = listOf(homeDto)), "\"1\""),
                features = defaultFeatures(),
            )
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()

        holder.upsertGeofence(draft(id = "gf_school", name = "School"))
        var state = holder.state.value as GeofencesUiState.Content
        assertEquals(setOf("gf_home", "gf_school"), state.geofences.map { it.geofenceId }.toSet())

        holder.upsertGeofence(draft(id = "gf_home", name = "Home (renamed)"))
        state = holder.state.value as GeofencesUiState.Content
        assertEquals(2, state.geofences.size)
        assertEquals("Home (renamed)", state.geofences.single { it.geofenceId == "gf_home" }.name)
    }

    @Test
    fun `removeGeofence drops only the named entry`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(
                    GeofenceConfigResponseDto(version = 1, geofences = listOf(homeDto, homeDto.copy(geofenceId = "gf_school"))),
                    "\"1\"",
                ),
                features = defaultFeatures(),
            )
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()

        holder.removeGeofence("gf_home")

        val state = holder.state.value as GeofencesUiState.Content
        assertEquals(listOf("gf_school"), state.geofences.map { it.geofenceId })
    }

    @Test
    fun `save success replaces state with the server's new version and etag`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 1, geofences = listOf(homeDto)), "\"1\""),
                features = defaultFeatures(),
            )
            replaceGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 2, geofences = listOf(homeDto)), "\"2\""),
                features = defaultFeatures(),
            )
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()

        holder.save()

        val state = holder.state.value as GeofencesUiState.Content
        assertEquals("\"2\"", state.etag)
        assertEquals(false, state.isSaving)
        assertEquals(false, state.conflict)
        assertEquals("\"1\"", api.replaceGeofencesCalls.single().first)
    }

    @Test
    fun `a 409 conflict re-fetches, adopts the fresh etag, and keeps the pending edit`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 1, geofences = listOf(homeDto)), "\"1\""),
                features = defaultFeatures(),
            )
            replaceGeofencesResult = ApiResult.Failure(
                ApiError.GeofenceVersionConflict(currentEtag = "\"3\"", message = "stale", requestId = "r_1"),
            )
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()
        holder.upsertGeofence(homeDto.toUiForTest().copy(name = "Home (pending edit)"))

        // The conflict handler re-fetches; script what that second getGeofences() call returns —
        // the server's own (different) copy, e.g. reflecting someone else's concurrent edit.
        api.getGeofencesResult = ApiResult.Success(
            ETagged(
                GeofenceConfigResponseDto(version = 3, geofences = listOf(homeDto.copy(name = "Home (server edit)"))),
                "\"3\"",
            ),
            features = defaultFeatures(),
        )

        holder.save()

        val state = holder.state.value as GeofencesUiState.Content
        assertEquals("\"3\"", state.etag)
        assertTrue(state.conflict)
        assertEquals(false, state.isSaving)
        assertNull(state.saveError)
        // The pending edit is NOT silently discarded/overwritten by the server's concurrent copy.
        assertEquals("Home (pending edit)", state.geofences.single { it.geofenceId == "gf_home" }.name)
        assertEquals(2, api.getGeofencesCalls.size)

        // A subsequent save uses the freshly-adopted etag, not the stale original one.
        api.replaceGeofencesResult = ApiResult.Success(
            ETagged(GeofenceConfigResponseDto(version = 4, geofences = listOf(homeDto)), "\"4\""),
            features = defaultFeatures(),
        )
        holder.save()
        assertEquals("\"3\"", api.replaceGeofencesCalls[1].first)
    }

    @Test
    fun `a non-conflict save failure surfaces the user-facing saveError, never the raw server message`() = runTest {
        val api = FakeGeofenceApi().apply {
            getGeofencesResult = ApiResult.Success(
                ETagged(GeofenceConfigResponseDto(version = 1, geofences = listOf(homeDto)), "\"1\""),
                features = defaultFeatures(),
            )
            replaceGeofencesResult = ApiResult.Failure(
                ApiError.LimitExceeded("maxGeofences", "raw debug text from server", "r_2"),
            )
        }
        val holder = GeofencesStateHolder(api, backgroundScope)
        runCurrent()

        holder.save()

        val state = holder.state.value as GeofencesUiState.Content
        assertEquals("You've reached your geofence limit for this plan.", state.saveError)
        assertEquals(false, state.conflict)
        assertEquals(false, state.isSaving)
        assertEquals("\"1\"", state.etag)
        assertEquals(1, state.geofences.size)
    }

    private fun draft(
        id: String = "gf_home",
        name: String = "Home",
        radiusM: Double = 150.0,
    ) = GeofenceUi(id, name, 51.0, 3.7, radiusM, "home", true, true)

    private fun GeofenceDto.toUiForTest() = GeofenceUi(geofenceId, name, lat, lon, radiusM, icon, notifyOnEnter, notifyOnExit)
}
