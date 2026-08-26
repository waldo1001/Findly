package com.findly.android.ui.history

import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.HistoryPointDto
import com.findly.android.network.dto.LocationHistoryResponseDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** [HistoryStateHolder] is pure Kotlin — tested directly with [FakeLocationsApi]
 * (specs/003-android-client.md §14, §16: "pagination for history"). */
class HistoryStateHolderTest {

    private fun point(deviceId: String, recordedAt: String) = HistoryPointDto(
        deviceId = deviceId,
        recordedAt = recordedAt,
        lat = 51.0,
        lon = 3.7,
        accuracyM = 10.0,
        batteryPct = 80,
        source = "periodic",
    )

    @Test
    fun `initial state is Idle before any query`() = runTest {
        val holder = HistoryStateHolder(FakeLocationsApi())
        assertTrue(holder.state.value is HistoryUiState.Idle)
    }

    @Test
    fun `load populates points and nextCursor from the first page`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(
                ApiResult.Success(
                    LocationHistoryResponseDto(points = listOf(point("d1", "t1")), nextCursor = "cursor-1"),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = HistoryStateHolder(api)

        holder.load(userId = "u1", from = "2026-07-01", to = "2026-07-19")

        val state = holder.state.value
        assertTrue(state is HistoryUiState.Content)
        state as HistoryUiState.Content
        assertEquals(listOf("t1"), state.points.map { it.recordedAt })
        assertEquals("cursor-1", state.nextCursor)
        val call = api.getLocationHistoryCalls.single()
        assertEquals("u1", call.userId)
        assertEquals("2026-07-01", call.from)
        assertEquals("2026-07-19", call.to)
        assertEquals(null, call.cursor)
    }

    @Test
    fun `loadMore appends the next page using the cursor from the previous page`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(
                ApiResult.Success(
                    LocationHistoryResponseDto(points = listOf(point("d1", "t1")), nextCursor = "cursor-1"),
                    features = defaultFeatures(),
                ),
            )
            historyResults.add(
                ApiResult.Success(
                    LocationHistoryResponseDto(points = listOf(point("d1", "t2")), nextCursor = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = HistoryStateHolder(api)
        holder.load(userId = "u1", from = "2026-07-01", to = "2026-07-19", deviceId = "d1")

        holder.loadMore()

        val state = holder.state.value as HistoryUiState.Content
        assertEquals(listOf("t1", "t2"), state.points.map { it.recordedAt })
        assertEquals(null, state.nextCursor)
        assertEquals(false, state.isLoadingMore)
        assertEquals(2, api.getLocationHistoryCalls.size)
        val secondCall = api.getLocationHistoryCalls[1]
        assertEquals("cursor-1", secondCall.cursor)
        assertEquals("d1", secondCall.deviceId)
    }

    @Test
    fun `loadMore is a no-op once nextCursor is exhausted`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(
                ApiResult.Success(
                    LocationHistoryResponseDto(points = listOf(point("d1", "t1")), nextCursor = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = HistoryStateHolder(api)
        holder.load(userId = "u1", from = "2026-07-01", to = "2026-07-19")

        holder.loadMore()

        assertEquals(1, api.getLocationHistoryCalls.size)
        assertEquals(1, (holder.state.value as HistoryUiState.Content).points.size)
    }

    @Test
    fun `loadMore before any load is a no-op and leaves state Idle`() = runTest {
        val api = FakeLocationsApi()
        val holder = HistoryStateHolder(api)

        holder.loadMore()

        assertTrue(holder.state.value is HistoryUiState.Idle)
        assertEquals(0, api.getLocationHistoryCalls.size)
    }

    @Test
    fun `a failed load surfaces Error with the user-facing message, never the raw server message`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(
                ApiResult.Failure(ApiError.ValidationFailed(null, "beyondRetention", "raw debug text from server", "r_1")),
            )
        }
        val holder = HistoryStateHolder(api)

        holder.load(userId = "u1", from = "2020-01-01", to = "2020-01-31")

        val state = holder.state.value
        assertTrue(state is HistoryUiState.Error)
        assertEquals(
            "That date range is further back than your plan allows.",
            (state as HistoryUiState.Error).message,
        )
    }

    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule — GET /locations/history is
    // family-scoped (001 §1.6).

    @Test
    fun `PROFILE_NOT_FOUND routes to Onboarding profile-less instead of Error`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1")))
        }
        val holder = HistoryStateHolder(api)

        holder.load(userId = "u1", from = "2026-07-01", to = "2026-07-19")

        val state = holder.state.value
        assertTrue(state is HistoryUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as HistoryUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `FAMILY_NOT_FOUND routes to Onboarding family-less instead of Error`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1")))
        }
        val holder = HistoryStateHolder(api)

        holder.load(userId = "u1", from = "2026-07-01", to = "2026-07-19")

        val state = holder.state.value
        assertTrue(state is HistoryUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as HistoryUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `a fresh load replaces any previous results rather than appending`() = runTest {
        val api = FakeLocationsApi().apply {
            historyResults.add(
                ApiResult.Success(
                    LocationHistoryResponseDto(points = listOf(point("d1", "t1")), nextCursor = null),
                    features = defaultFeatures(),
                ),
            )
            historyResults.add(
                ApiResult.Success(
                    LocationHistoryResponseDto(points = listOf(point("d1", "t9")), nextCursor = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = HistoryStateHolder(api)
        holder.load(userId = "u1", from = "2026-07-01", to = "2026-07-19")

        holder.load(userId = "u1", from = "2026-08-01", to = "2026-08-19")

        val state = holder.state.value as HistoryUiState.Content
        assertEquals(listOf("t9"), state.points.map { it.recordedAt })
    }
}
