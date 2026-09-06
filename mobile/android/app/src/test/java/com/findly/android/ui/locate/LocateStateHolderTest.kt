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

    // specs/009-device-runtime.md §5.1 (amended 2026-09-06, A39's review, finding 6): the poll
    // timeout must be measured as a *locally elapsed* duration from receipt of the create
    // response, using the server-computed window (createdAt..expiresAt) - never by comparing
    // `now()` directly against the absolute `expiresAt` instant. A device whose clock runs fast
    // previously satisfied that absolute comparison on the very first poll tick and reported
    // UNREACHABLE before the target could possibly have answered. The two tests below replace the
    // old (buggy) "now() reaching expiresAt stops polling" test, which encoded exactly that bug.

    @Test
    fun `a skewed absolute clock reading does not shorten the poll window`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(LatestLocationsResponseDto(members = emptyList()), features = defaultFeatures())
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(pendingResponse())
        }
        // now() is pinned hours past expiresAt and never advances in this fixed-clock fixture -
        // the OLD implementation compared this absolute reading straight against expiresAt and
        // would have declared UNREACHABLE on the very first tick below.
        val holder = holder(api, locationsApi, nowIso = "2026-07-19T11:00:00Z")

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        advanceTimeBy(2000); runCurrent()
        assertTrue("a skewed clock reading must not cut the 60s window short", holder.state.value is LocateUiState.Polling)
        assertEquals(1, api.getLocateRequestCalls.size)

        advanceTimeBy(2000); runCurrent()
        assertTrue("still well within the 60s window", holder.state.value is LocateUiState.Polling)
        assertEquals(2, api.getLocateRequestCalls.size)
        assertEquals(0, locationsApi.getLatestLocationsCallCount)
    }

    @Test
    fun `the poll window still ends after its full locally-elapsed duration, immune to a skewed absolute clock`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(LatestLocationsResponseDto(members = emptyList()), features = defaultFeatures())
        }
        val api = FakeLocateApi().apply {
            createLocateRequestResult = createResult()
            pollResults.add(pendingResponse())
        }
        // A constant multi-hour forward skew, but ticking at the real rate from there
        // (testScheduler.currentTime tracks true virtual elapsed time) - Duration.between(receivedAt,
        // now()) cancels the skew, so the fallback fires only once the server-computed 60s window
        // (createdAt..expiresAt, from the fixtures above) has truly elapsed - not immediately off
        // the skewed absolute reading.
        val holder = LocateStateHolder(
            api,
            locationsApi,
            backgroundScope,
            pollIntervalMillis = 2000L,
            now = { Instant.parse("2026-07-19T11:00:00Z").plusMillis(testScheduler.currentTime) },
        )

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        // 29 ticks (58s of the 60s window) - must still be polling.
        repeat(29) {
            advanceTimeBy(2000); runCurrent()
        }
        assertTrue("58s elapsed of a 60s window - must still be polling", holder.state.value is LocateUiState.Polling)
        assertEquals(29, api.getLocateRequestCalls.size)

        // 30th tick (60s) - the window has now fully elapsed locally.
        advanceTimeBy(2000); runCurrent()
        val state = holder.state.value
        assertTrue(state is LocateUiState.Terminal)
        assertEquals(LocateOutcome.UNREACHABLE, (state as LocateUiState.Terminal).outcome)
        assertEquals(30, api.getLocateRequestCalls.size)
        assertEquals(1, locationsApi.getLatestLocationsCallCount)

        // No further polling after the fallback resolved.
        advanceTimeBy(10_000); runCurrent()
        assertEquals(30, api.getLocateRequestCalls.size)
    }

    // specs/009-device-runtime.md §5.1 (amended 2026-09-06, A39's final round, finding 2): a
    // zero-length poll window (`createdAt == expiresAt`) is malformed data, not a legitimately
    // already-expired request — `takeIf { !it.isNegative }` let `Duration.ZERO` through, so
    // `hasElapsedPollWindow` was satisfied on the very first poll tick and reported UNREACHABLE
    // before the target could possibly have answered, reintroducing the instant-UNREACHABLE bug
    // finding 6 fixed, from the malformed-data direction instead of the clock-skew one. A
    // malformed window must behave like an unparseable one: never expires locally.

    @Test
    fun `a zero-length poll window is treated as malformed and never expires the poll locally`() = runTest {
        val zeroWindowCreatedAt = "2026-07-19T09:05:12Z"
        val zeroWindowExpiresAt = "2026-07-19T09:05:12Z" // createdAt == expiresAt: malformed, not "already expired"
        val locationsApi = FakeLocationsApi()
        val api = FakeLocateApi().apply {
            createLocateRequestResult = ApiResult.Success(
                LocateRequestDto(
                    requestId = "lr_1",
                    status = "pending",
                    targetUserId = "u2",
                    targetDeviceId = "d2",
                    createdAt = zeroWindowCreatedAt,
                    expiresAt = zeroWindowExpiresAt,
                    lastKnown = null,
                ),
                features = defaultFeatures(),
            )
            pollResults.add(
                ApiResult.Success(
                    LocateRequestStatusResponseDto(
                        "lr_1", "pending", zeroWindowCreatedAt, zeroWindowExpiresAt,
                        fulfilledAt = null, late = false, fix = null,
                    ),
                    features = defaultFeatures(),
                ),
            )
        }
        val holder = holder(api, locationsApi, nowIso = zeroWindowCreatedAt)

        holder.requestLocate(targetUserId = "u2")
        runCurrent()

        // The very first poll tick used to trip `hasElapsedPollWindow` immediately against a
        // Duration.ZERO window and jump straight to the UNREACHABLE fallback.
        advanceTimeBy(2000); runCurrent()
        assertTrue(
            "a zero-length window must be treated as malformed (never expires locally), not as already elapsed",
            holder.state.value is LocateUiState.Polling,
        )
        assertEquals(0, locationsApi.getLatestLocationsCallCount)
    }

    // specs/009-device-runtime.md §5.1 "Requester side" fallback device-selection (finding 12,
    // A39's review): every existing fallback test above uses an empty member list or a single
    // device, so `firstOrNull { it.deviceId == targetDeviceId }` never had to discriminate between
    // devices. This adds a decoy device (a different member) with a *newer* recordedAt than the
    // target device's own — proving the filter selects strictly by deviceId, not by "any newer
    // report".

    @Test
    fun `the fallback discriminates the target device from a decoy with a newer recordedAt`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        // The decoy: a different member/device reporting *after* createdAt - if the
                        // fallback picked "any device with a newer recordedAt" instead of filtering
                        // by deviceId first, it would wrongly surface this device's position.
                        LatestMemberDto(
                            userId = "u3", displayName = "Decoy",
                            devices = listOf(
                                LatestDeviceDto(
                                    deviceId = "d3", deviceName = "Decoy phone", lat = 52.0, lon = 4.0,
                                    accuracyM = 5.0, recordedAt = "2026-07-19T09:07:00Z", receivedAt = "2026-07-19T09:07:01Z",
                                    batteryPct = 90, source = "periodic", trackingEnabled = true, syncIntervalMinutes = 15,
                                    isStale = false,
                                ),
                            ),
                        ),
                        // The actual target device: recordedAt is *not* newer than createdAt, so
                        // this must still resolve UNREACHABLE.
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
        assertEquals(LocateOutcome.UNREACHABLE, state.outcome)
        assertNull(state.fix)
    }

    // specs/009-device-runtime.md §5.1 fallback LATE-with-a-null-fix (finding 13, A39's review):
    // the outcome must not be fixed at LATE off `recordedAt` alone when the resulting fix itself
    // is null (lat/lon absent) - that used to produce Terminal(outcome = LATE, fix = null), which
    // the screen renders as a stale lastKnown position under a "Located" chip.

    @Test
    fun `a newer recordedAt with no lat-lon does not surface LATE with a null fix`() = runTest {
        val locationsApi = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u2", displayName = "Noor",
                            devices = listOf(
                                LatestDeviceDto(
                                    deviceId = "d2", deviceName = "Pixel", lat = null, lon = null,
                                    accuracyM = null, recordedAt = "2026-07-19T09:06:00Z", receivedAt = "2026-07-19T09:06:01Z",
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
        assertEquals(LocateOutcome.UNREACHABLE, state.outcome)
        assertNull(state.fix)
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
