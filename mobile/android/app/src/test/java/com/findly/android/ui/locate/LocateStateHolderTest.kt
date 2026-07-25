package com.findly.android.ui.locate

import com.findly.android.fakes.FakeLocateApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LastKnownDto
import com.findly.android.network.dto.LocateFixDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.dto.LocateRequestStatusResponseDto
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [LocateStateHolder] is pure Kotlin — tested with [FakeLocateApi] and `kotlinx-coroutines-test`
 * virtual time, so the real 2 s poll interval (001-api-contract.md §6.2) never actually elapses
 * (specs/003-android-client.md §14, §16: "poll-until-terminal for locate"). Each poll cycle is
 * driven explicitly with `advanceTimeBy(2000) + runCurrent()` (not `advanceUntilIdle()`, which
 * would race the whole sequence to completion in one shot and hide the intermediate `Polling`
 * states this test exists to verify). */
class LocateStateHolderTest {

    private fun pendingResponse(requestId: String = "lr_1") = ApiResult.Success(
        LocateRequestStatusResponseDto(requestId, "pending", "2026-07-19T09:06:12Z", fix = null),
        features = defaultFeatures(),
    )

    @Test
    fun `poll-until-terminal advances through pending responses to a fulfilled terminal state`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Success(
                LocateRequestDto(
                    requestId = "lr_1",
                    status = "pending",
                    targetUserId = "u2",
                    targetDeviceId = "d2",
                    expiresAt = "2026-07-19T09:06:12Z",
                    lastKnown = LastKnownDto("d2", 51.0, 3.7, 15.0, "2026-07-19T08:50:00Z"),
                ),
                features = defaultFeatures(),
            )
            pollResults.add(pendingResponse())
            pollResults.add(pendingResponse())
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto(
                        requestId = "lr_1",
                        status = "fulfilled",
                        expiresAt = "2026-07-19T09:06:12Z",
                        fix = LocateFixDto("d2", "f1", "2026-07-19T09:05:59Z", 51.0544, 3.7170, 4.8, batteryPct = 77, source = "locate"),
                    ),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = LocateStateHolder(api, backgroundScope, pollIntervalMillis = 2000L)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        val afterCreate = holder.state.value
        assertTrue(afterCreate is LocateUiState.Polling)
        afterCreate as LocateUiState.Polling
        assertEquals("lr_1", afterCreate.requestId)
        assertEquals(51.0, afterCreate.lastKnown?.lat)
        assertEquals(0, api.getLocateRequestCalls.size)
        assertEquals(listOf("u2" to null), api.createLocateRequestCalls)

        advanceTimeBy(2000); runCurrent()
        assertTrue("still polling after 1st non-terminal response", holder.state.value is LocateUiState.Polling)
        assertEquals(1, api.getLocateRequestCalls.size)

        advanceTimeBy(2000); runCurrent()
        assertTrue("still polling after 2nd non-terminal response", holder.state.value is LocateUiState.Polling)
        assertEquals(2, api.getLocateRequestCalls.size)

        advanceTimeBy(2000); runCurrent()
        val finalState = holder.state.value
        assertTrue(finalState is LocateUiState.Terminal)
        finalState as LocateUiState.Terminal
        assertEquals("fulfilled", finalState.status)
        assertEquals(51.0544, finalState.fix?.lat)
        assertEquals(3, api.getLocateRequestCalls.size)

        // No further poll happens once terminal (the loop returned).
        advanceTimeBy(4000); runCurrent()
        assertEquals(3, api.getLocateRequestCalls.size)
    }

    @Test
    fun `an immediate create failure surfaces Error without ever polling`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Failure(ApiError.TrackingPaused(null, "paused", "r_1"))
        }
        val holder = LocateStateHolder(api, backgroundScope, pollIntervalMillis = 2000L)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        assertTrue(holder.state.value is LocateUiState.Error)

        advanceTimeBy(10_000); runCurrent()
        assertEquals(0, api.getLocateRequestCalls.size)
    }

    @Test
    fun `a poll failure surfaces Error and stops the loop`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Success(
                LocateRequestDto("lr_1", "pending", "u2", "d2", "2026-07-19T09:06:12Z", lastKnown = null),
                features = defaultFeatures(),
            )
            pollResults.add(ApiResult.Failure(ApiError.LocateRequestNotFound("gone", "r_2")))
        }
        val holder = LocateStateHolder(api, backgroundScope, pollIntervalMillis = 2000L)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Error)
        assertEquals(1, api.getLocateRequestCalls.size)

        advanceTimeBy(10_000); runCurrent()
        assertEquals(1, api.getLocateRequestCalls.size)
    }

    @Test
    fun `pushFailed is treated as terminal and still surfaces lastKnown`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Success(
                LocateRequestDto(
                    "lr_1", "pending", "u2", "d2", "2026-07-19T09:06:12Z",
                    lastKnown = LastKnownDto("d2", 51.0, 3.7, 15.0, "2026-07-19T08:50:00Z"),
                ),
                features = defaultFeatures(),
            )
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto("lr_1", "pushFailed", "2026-07-19T09:06:12Z", fix = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = LocateStateHolder(api, backgroundScope, pollIntervalMillis = 2000L)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        state as LocateUiState.Terminal
        assertEquals("pushFailed", state.status)
        assertNull(state.fix)
        assertEquals(51.0, state.lastKnown?.lat)
    }

    @Test
    fun `expired is treated as terminal`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Success(
                LocateRequestDto("lr_1", "pending", "u2", "d2", "2026-07-19T09:06:12Z", lastKnown = null),
                features = defaultFeatures(),
            )
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto("lr_1", "expired", "2026-07-19T09:06:12Z", fix = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = LocateStateHolder(api, backgroundScope, pollIntervalMillis = 2000L)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        assertEquals("expired", (holder.state.value as LocateUiState.Terminal).status)
    }

    @Test
    fun `starting a new request cancels the previous poll loop`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Success(
                LocateRequestDto("lr_1", "pending", "u2", "d2", "2026-07-19T09:06:12Z", lastKnown = null),
                features = defaultFeatures(),
            )
            // Only lr_2's poll response is seeded — if the first (lr_1) loop weren't cancelled, it
            // would poll too and this fake would throw ("pollResults was never seeded") once
            // exhausted differently, or — worse — silently reuse this lr_2 response for lr_1's
            // poll, which the assertion below still catches via the resulting state's requestId.
            pollResults.add(pendingResponse(requestId = "lr_2"))
        }
        val holder = LocateStateHolder(api, backgroundScope, pollIntervalMillis = 2000L)
        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        // A second request before the first poll loop ever fires must cancel the first loop.
        api.createLocateRequestResult = ApiResult.Success(
            LocateRequestDto("lr_2", "pending", "u3", "d3", "2026-07-19T09:07:00Z", lastKnown = null),
            features = defaultFeatures(),
        )
        holder.requestLocate(targetUserId = "u3")
        runCurrent()

        advanceTimeBy(2000); runCurrent()

        // Exactly one poll happened (lr_2's) — the first (lr_1) loop was cancelled before its
        // own delay ever elapsed, so it never called getLocateRequest at all.
        assertEquals(1, api.getLocateRequestCalls.size)
        assertEquals("lr_2", api.getLocateRequestCalls.single())
        val state = holder.state.value
        assertTrue(state is LocateUiState.Polling)
        assertEquals("lr_2", (state as LocateUiState.Polling).requestId)
    }
}
