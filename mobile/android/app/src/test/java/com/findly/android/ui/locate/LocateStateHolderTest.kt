package com.findly.android.ui.locate

import com.findly.android.fakes.FakeLocateApi
import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LastKnownDto
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import com.findly.android.network.dto.LatestMemberDto
import com.findly.android.network.dto.LocateFixDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.dto.LocateRequestStatusResponseDto
import com.findly.android.ui.onboarding.OnboardingVariant
import java.time.Instant
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [LocateStateHolder] is pure Kotlin — tested with [FakeLocateApi]/[FakeLocationsApi] and
 * `kotlinx-coroutines-test` virtual time, so the real 2 s poll interval (001-api-contract.md
 * §6.2) never actually elapses (specs/003-android-client.md §14, §16: "poll-until-terminal for
 * locate"). Each poll cycle is driven explicitly with `advanceTimeBy(2000) + runCurrent()` (not
 * `advanceUntilIdle()`, which would race the whole sequence to completion in one shot and hide the
 * intermediate `Polling` states this test exists to verify).
 *
 * specs/009-device-runtime.md §5.1 "Requester side" (amended 2026-09-06, A39): polling now stops
 * at a terminal status **or `expiresAt`**, and — before ever reporting [LocateOutcome.UNREACHABLE]
 * — the holder performs exactly one `GET /locations/latest` fallback check; a `recordedAt` newer
 * than the request's `createdAt` is shown as [LocateOutcome.LATE]. `now` is injected (not
 * `Instant::now`) so the expiresAt-timeout path is deterministic under virtual time.
 */
class LocateStateHolderTest {

    private val createdAt = "2026-07-19T09:05:12Z"
    private val expiresAt = "2026-07-19T09:06:12Z" // createdAt + 60s in these fixtures for brevity

    private fun pendingResponse(requestId: String = "lr_1") = ApiResult.Success(
        LocateRequestStatusResponseDto(requestId, "pending", createdAt, expiresAt, fulfilledAt = null, late = false, fix = null),
        features = defaultFeatures(),
    )

    private fun createResult(
        requestId: String = "lr_1",
        targetDeviceId: String = "d2",
        lastKnown: LastKnownDto? = LastKnownDto("d2", 51.0, 3.7, 15.0, "2026-07-19T08:50:00Z"),
    ) = ApiResult.Success(
        LocateRequestDto(
            requestId = requestId,
            status = "pending",
            targetUserId = "u2",
            targetDeviceId = targetDeviceId,
            createdAt = createdAt,
            expiresAt = expiresAt,
            lastKnown = lastKnown,
        ),
        features = defaultFeatures(),
    )

    private fun TestScope.holder(
        locateApi: FakeLocateApi,
        locationsApi: FakeLocationsApi = FakeLocationsApi(),
        nowIso: String = "2026-07-19T09:05:12Z",
    ) = LocateStateHolder(locateApi, locationsApi, backgroundScope, pollIntervalMillis = 2000L, now = { Instant.parse(nowIso) })

    @Test
    fun `poll-until-terminal advances through pending responses to a fresh fulfilled terminal state`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(pendingResponse())
            pollResults.add(pendingResponse())
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto(
                        requestId = "lr_1",
                        status = "fulfilled",
                        createdAt = createdAt,
                        expiresAt = expiresAt,
                        fulfilledAt = "2026-07-19T09:05:59Z",
                        late = false,
                        fix = LocateFixDto("d2", "f1", "2026-07-19T09:05:59Z", 51.0544, 3.7170, 4.8, batteryPct = 77, source = "locate"),
                    ),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api)

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
        assertEquals(LocateOutcome.FRESH, finalState.outcome)
        assertEquals(51.0544, finalState.fix?.lat)
        assertEquals(3, api.getLocateRequestCalls.size)

        // No further poll happens once terminal (the loop returned).
        advanceTimeBy(4000); runCurrent()
        assertEquals(3, api.getLocateRequestCalls.size)
    }

    @Test
    fun `a fulfilled response with late true surfaces the LATE outcome without any fallback call`() = runTest {
        val locationsApi = FakeLocationsApi()
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto(
                        requestId = "lr_1", status = "fulfilled", createdAt = createdAt, expiresAt = expiresAt,
                        fulfilledAt = "2026-07-19T09:16:00Z", late = true,
                        fix = LocateFixDto("d2", "f1", "2026-07-19T09:15:59Z", 51.0, 3.7, 4.8, batteryPct = 50, source = "locate"),
                    ),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api, locationsApi)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        state as LocateUiState.Terminal
        assertEquals(LocateOutcome.LATE, state.outcome)
        assertEquals(0, locationsApi.getLatestLocationsCallCount)
    }

    @Test
    fun `an immediate create failure surfaces Error without ever polling`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Failure(ApiError.TrackingPaused(null, "paused", "r_1"))
        }
        val holder = holder(api)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        assertTrue(holder.state.value is LocateUiState.Error)

        advanceTimeBy(10_000); runCurrent()
        assertEquals(0, api.getLocateRequestCalls.size)
    }

    @Test
    fun `a poll failure surfaces Error and stops the loop`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult(lastKnown = null)
            pollResults.add(ApiResult.Failure(ApiError.LocateRequestNotFound("gone", "r_2")))
        }
        val holder = holder(api)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Error)
        assertEquals(1, api.getLocateRequestCalls.size)

        advanceTimeBy(10_000); runCurrent()
        assertEquals(1, api.getLocateRequestCalls.size)
    }

    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule — Locate has no separate eager
    // load, so the create/poll call itself is its load path; both are family-scoped (001 §1.6).

    @Test
    fun `an immediate create PROFILE_NOT_FOUND routes to Onboarding profile-less instead of Error`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = holder(api)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as LocateUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `a poll FAMILY_NOT_FOUND routes to Onboarding family-less and stops the loop`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult(lastKnown = null)
            pollResults.add(ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_2")))
        }
        val holder = holder(api)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as LocateUiState.RouteToOnboarding).variant)
        advanceTimeBy(10_000); runCurrent()
        assertEquals(1, api.getLocateRequestCalls.size)
    }

    @Test
    fun `pushFailed with no fresher position falls back to UNREACHABLE via the latest-location check`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(LatestLocationsResponseDto(members = emptyList()), features = defaultFeatures())
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto("lr_1", "pushFailed", createdAt, expiresAt, fulfilledAt = null, late = false, fix = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api, locationsApi)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        state as LocateUiState.Terminal
        assertEquals("pushFailed", state.status)
        assertEquals(LocateOutcome.UNREACHABLE, state.outcome)
        assertNull(state.fix)
        assertEquals(51.0, state.lastKnown?.lat)
        assertEquals(1, locationsApi.getLatestLocationsCallCount)
    }

    @Test
    fun `pushFailed but the target device already reported after createdAt surfaces LATE instead`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u2", displayName = "Noor",
                            devices = listOf(
                                LatestDeviceDto(
                                    deviceId = "d2", deviceName = "Pixel", lat = 51.06, lon = 3.72,
                                    accuracyM = 10.0, recordedAt = "2026-07-19T09:06:00Z", receivedAt = "2026-07-19T09:06:01Z",
                                    batteryPct = 40, source = "periodic", trackingEnabled = true, syncIntervalMinutes = 15,
                                    isStale = false,
                                ),
                            ),
                        ),
                    ),
                ),
                features = defaultFeatures(),
            )
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto("lr_1", "pushFailed", createdAt, expiresAt, fulfilledAt = null, late = false, fix = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api, locationsApi)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        state as LocateUiState.Terminal
        assertEquals(LocateOutcome.LATE, state.outcome)
        assertEquals(51.06, state.fix?.lat)
        assertEquals("d2", state.fix?.deviceId)
        assertEquals(1, locationsApi.getLatestLocationsCallCount)
    }

    @Test
    fun `expired with a recordedAt not newer than createdAt stays UNREACHABLE`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u2", displayName = "Noor",
                            devices = listOf(
                                LatestDeviceDto(
                                    deviceId = "d2", deviceName = "Pixel", lat = 51.0, lon = 3.7,
                                    accuracyM = 10.0, recordedAt = "2026-07-19T08:50:00Z", receivedAt = "2026-07-19T08:50:01Z",
                                    batteryPct = 40, source = "periodic", trackingEnabled = true, syncIntervalMinutes = 15,
                                    isStale = true,
                                ),
                            ),
                        ),
                    ),
                ),
                features = defaultFeatures(),
            )
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto("lr_1", "expired", createdAt, expiresAt, fulfilledAt = null, late = false, fix = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api, locationsApi)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        state as LocateUiState.Terminal
        assertEquals("expired", state.status)
        assertEquals(LocateOutcome.UNREACHABLE, state.outcome)
        assertNull(state.fix)
    }

    @Test
    fun `a pending response reaching expiresAt by wall clock stops polling and falls back`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(LatestLocationsResponseDto(members = emptyList()), features = defaultFeatures())
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            // Server keeps reporting "pending" (e.g. hasn't been polled again server-side to lazily
            // flip to expired) - the client's own now() reaching expiresAt must still stop the loop.
            pollResults.add(pendingResponse())
        }
        // now() is fixed at exactly expiresAt for the poll tick.
        val holder = holder(api, locationsApi, nowIso = expiresAt)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        state as LocateUiState.Terminal
        assertEquals(LocateOutcome.UNREACHABLE, state.outcome)
        assertEquals(1, api.getLocateRequestCalls.size)
        assertEquals(1, locationsApi.getLatestLocationsCallCount)

        // No further polling after the fallback resolved.
        advanceTimeBy(10_000); runCurrent()
        assertEquals(1, api.getLocateRequestCalls.size)
    }

    @Test
    fun `a locationsApi fallback failure is treated as UNREACHABLE rather than crashing`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto("lr_1", "expired", createdAt, expiresAt, fulfilledAt = null, late = false, fix = null),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api, locationsApi)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()
        advanceTimeBy(2000); runCurrent()

        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        assertEquals(LocateOutcome.UNREACHABLE, (state as LocateUiState.Terminal).outcome)
    }

    @Test
    fun `starting a new request cancels the previous poll loop`() = runTest {
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult(lastKnown = null)
            // Only lr_2's poll response is seeded — if the first (lr_1) loop weren't cancelled, it
            // would poll too and this fake would throw ("pollResults was never seeded") once
            // exhausted differently, or — worse — silently reuse this lr_2 response for lr_1's
            // poll, which the assertion below still catches via the resulting state's requestId.
            pollResults.add(pendingResponse(requestId = "lr_2"))
        }
        val holder = holder(api)
        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        // A second request before the first poll loop ever fires must cancel the first loop.
        api.createLocateRequestResult = createResult(requestId = "lr_2", targetDeviceId = "d3", lastKnown = null)
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
