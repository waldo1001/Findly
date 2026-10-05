package com.findly.android.ui.map

import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import com.findly.android.network.dto.LatestMemberDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [MapStateHolder] is pure Kotlin (specs/003-android-client.md §14) — tested with a
 * `backgroundScope` + [FakeLocationsApi], no Robolectric/emulator (001-api-contract.md §5.2). */
@OptIn(ExperimentalCoroutinesApi::class)
class MapStateHolderTest {

    @Test
    fun `initial load populates the roster from getLatestLocations`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u1",
                            displayName = "Eric",
                            devices = listOf(
                                LatestDeviceDto(
                                    deviceId = "d1",
                                    deviceName = "Pixel 8",
                                    lat = 51.0543,
                                    lon = 3.7174,
                                    accuracyM = 15.0,
                                    recordedAt = "2026-07-19T09:05:12Z",
                                    receivedAt = "2026-07-19T09:05:14Z",
                                    batteryPct = 78,
                                    source = "periodic",
                                    trackingEnabled = true,
                                    syncIntervalMinutes = 15,
                                    isStale = false,
                                ),
                            ),
                        ),
                    ),
                ),
                features = defaultFeatures(),
            )
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is MapUiState.Content)
        state as MapUiState.Content
        val member = state.members.single()
        assertEquals("Eric", member.displayName)
        val device = member.devices.single()
        assertEquals(51.0543, device.lat)
        assertTrue(device.hasLocation)
        assertEquals(false, device.isStale)
    }

    @Test
    fun `a member with no registered devices still appears with an empty device list`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(LatestMemberDto(userId = "u2", displayName = "Noor", devices = emptyList())),
                ),
                features = defaultFeatures(),
            )
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value as MapUiState.Content
        assertTrue(state.members.single().devices.isEmpty())
    }

    @Test
    fun `a never-reported device maps to hasLocation = false without crashing`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u2",
                            displayName = "Noor",
                            devices = listOf(
                                LatestDeviceDto(
                                    deviceId = "d2",
                                    deviceName = "Noor's phone",
                                    trackingEnabled = true,
                                    syncIntervalMinutes = 15,
                                ),
                            ),
                        ),
                    ),
                ),
                features = defaultFeatures(),
            )
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val device = (holder.state.value as MapUiState.Content).members.single().devices.single()
        assertEquals(false, device.hasLocation)
        assertEquals(null, device.isStale)
    }

    @Test
    fun `a failure surfaces Error with the user-facing message, never the raw server message`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Failure(ApiError.InternalError("raw debug text from server", "r_1"))
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is MapUiState.Error)
        assertEquals("Something went wrong on our end. Please try again.", (state as MapUiState.Error).message)
    }

    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule — GET /locations/latest is
    // family-scoped (001 §1.6), so both a confirmed PROFILE_NOT_FOUND and FAMILY_NOT_FOUND route
    // to Onboarding instead of the dead-end retryable card FamilyNotFound used to produce above.

    @Test
    fun `PROFILE_NOT_FOUND routes to Onboarding profile-less instead of Error`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_2"))
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is MapUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as MapUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `FAMILY_NOT_FOUND routes to Onboarding family-less instead of Error`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_3"))
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is MapUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as MapUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `refresh re-fetches and replaces the roster`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(members = emptyList()),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        assertEquals(1, api.getLatestLocationsCallCount)

        holder.refresh()

        assertEquals(2, api.getLatestLocationsCallCount)
        assertTrue(holder.state.value is MapUiState.Content)
    }

    // specs/010-app-shell-and-screen-ux.md §3.4/§3.5 — the camera policy: WHEN it re-runs (never
    // on an ordinary refresh) and the freshest-device selection target.

    @Test
    fun `the first load with a located point emits a camera command`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(members = listOf(memberWithOneDevice("u1", "Eric", "d1", 51.0543, 3.7174, "2026-08-26T10:00:00Z"))),
                features = defaultFeatures(),
            )
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value as MapUiState.Content
        assertEquals(
            MapCameraTarget.Center(51.0543, 3.7174, MapCamera.SINGLE_POINT_ZOOM),
            state.cameraCommand?.target,
        )
    }

    @Test
    fun `a refresh that changes the marker set never moves the camera again — the 010 §3_4 regression this task fixes`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(members = listOf(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-08-26T10:00:00Z"))),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        val firstCommand = (holder.state.value as MapUiState.Content).cameraCommand
        assertEquals(MapCameraTarget.Center(51.0, 3.0, MapCamera.SINGLE_POINT_ZOOM), firstCommand?.target)

        // A refresh with a materially different point set — exactly the case that used to yank
        // the camera on both platforms every time.
        api.getLatestLocationsResult = ApiResult.Success(
            LatestLocationsResponseDto(members = listOf(memberWithOneDevice("u1", "Eric", "d1", 60.0, 20.0, "2026-08-26T10:05:00Z"))),
            features = defaultFeatures(),
        )
        holder.refresh()

        val secondCommand = (holder.state.value as MapUiState.Content).cameraCommand
        assertEquals("no NEW camera command is minted on refresh", firstCommand, secondCommand)
    }

    @Test
    fun `selecting a member zooms to their freshest located device at SINGLE_POINT_ZOOM`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u1",
                            displayName = "Eric",
                            devices = listOf(
                                device("d1", 51.0, 3.0, "2026-08-26T09:00:00Z"),
                                device("d2", 52.0, 4.0, "2026-08-26T10:00:00Z"), // freshest
                            ),
                        ),
                    ),
                ),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        val beforeSeq = (holder.state.value as MapUiState.Content).cameraCommand?.seq

        holder.selectMember("u1")

        val state = holder.state.value as MapUiState.Content
        assertEquals("u1", state.selectedUserId)
        assertEquals(MapCameraTarget.Center(52.0, 4.0, MapCamera.SINGLE_POINT_ZOOM), state.cameraCommand?.target)
        assertNotEquals(beforeSeq, state.cameraCommand?.seq)
    }

    @Test
    fun `selecting a member with no located device highlights them without moving the camera`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        LatestMemberDto(
                            userId = "u9",
                            displayName = "Noor",
                            devices = listOf(LatestDeviceDto(deviceId = "d9", deviceName = "Phone", trackingEnabled = true, syncIntervalMinutes = 15)),
                        ),
                    ),
                ),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        val before = holder.state.value as MapUiState.Content

        holder.selectMember("u9")

        val after = holder.state.value as MapUiState.Content
        assertEquals("u9", after.selectedUserId)
        assertEquals("no fix to target — the camera MUST NOT move (010 §3.5)", before.cameraCommand, after.cameraCommand)
    }

    @Test
    fun `selecting the already-selected member deselects it`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(members = listOf(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-08-26T10:00:00Z"))),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.selectMember("u1")
        assertEquals("u1", (holder.state.value as MapUiState.Content).selectedUserId)

        holder.selectMember("u1")

        assertNull((holder.state.value as MapUiState.Content).selectedUserId)
    }

    @Test
    fun `deselect clears the selection without moving the camera`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(members = listOf(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-08-26T10:00:00Z"))),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.selectMember("u1")
        val selected = holder.state.value as MapUiState.Content
        assertEquals("u1", selected.selectedUserId)

        holder.deselect()

        val deselected = holder.state.value as MapUiState.Content
        assertNull(deselected.selectedUserId)
        assertEquals(selected.cameraCommand, deselected.cameraCommand)
    }

    @Test
    fun `deselect is a no-op when nothing is selected`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(members = emptyList()),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        holder.deselect()

        assertNull((holder.state.value as MapUiState.Content).selectedUserId)
    }

    @Test
    fun `fitAll re-runs the policy over current points on an explicit action`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(
                LatestLocationsResponseDto(
                    members = listOf(
                        memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-08-26T10:00:00Z"),
                        memberWithOneDevice("u2", "Noor", "d2", 60.0, 20.0, "2026-08-26T10:00:00Z"),
                    ),
                ),
                features = defaultFeatures(),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        val before = (holder.state.value as MapUiState.Content).cameraCommand

        holder.fitAll()

        val after = (holder.state.value as MapUiState.Content).cameraCommand
        assertNotEquals(before?.seq, after?.seq)
        assertTrue(after?.target is MapCameraTarget.Bounds)
    }

    // specs/010-app-shell-and-screen-ux.md §3.6 (A55) — data freshness. The trigger policy itself
    // (timer, visibility, in-flight gate) is MapRefreshControllerTest's; these pin how the holder
    // wires it and the failure/camera/selection rules that ride on it.

    private fun roster(vararg members: LatestMemberDto) = ApiResult.Success(
        LatestLocationsResponseDto(members = members.toList()),
        features = defaultFeatures(),
    )

    @Test
    fun `while visible the roster is re-fetched every 30 s and the new positions replace the old`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()
        assertEquals("first appearance: one fetch only", 1, api.getLatestLocationsCallCount)

        api.getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 52.0, 4.0, "2026-10-05T07:14:00Z"))
        advanceTimeBy(30_000)
        runCurrent()

        assertEquals(2, api.getLatestLocationsCallCount)
        val device = (holder.state.value as MapUiState.Content).members.single().devices.single()
        assertEquals(52.0, device.lat)
        assertEquals("2026-10-05T07:14:00Z", device.recordedAt)
    }

    @Test
    fun `nothing is fetched in the background - not before the map is visible, not after it is hidden`() = runTest {
        val api = FakeLocationsApi()
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        advanceTimeBy(5 * 60_000)
        runCurrent()
        assertEquals("never visible: only the initial load", 1, api.getLatestLocationsCallCount)

        holder.onVisible()
        holder.onHidden()
        advanceTimeBy(5 * 60_000)
        runCurrent()

        assertEquals("hidden: no timer", 1, api.getLatestLocationsCallCount)
    }

    @Test
    fun `a return to the foreground re-fetches the roster`() = runTest {
        val api = FakeLocationsApi()
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()
        holder.onHidden()
        assertEquals(1, api.getLatestLocationsCallCount)

        holder.onVisible()
        runCurrent()

        assertEquals(2, api.getLatestLocationsCallCount)
    }

    @Test
    fun `a failed periodic refresh keeps the last data on screen with no error`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()
        val before = holder.state.value as MapUiState.Content

        api.getLatestLocationsResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        advanceTimeBy(30_000)
        runCurrent()

        assertEquals(2, api.getLatestLocationsCallCount)
        assertEquals("the failure surfaces nothing - same Content, same roster", before, holder.state.value)
    }

    @Test
    fun `a failed foreground refresh also keeps the last data with no error`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()
        holder.onHidden()
        val before = holder.state.value

        api.getLatestLocationsResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        holder.onVisible()
        runCurrent()

        assertEquals(2, api.getLatestLocationsCallCount)
        assertEquals(before, holder.state.value)
    }

    @Test
    fun `a failed first load shows the error state, and a later successful periodic refresh recovers from it`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        assertTrue("only a FIRST load failure shows the error state", holder.state.value is MapUiState.Error)
        holder.onVisible()
        runCurrent()

        advanceTimeBy(30_000)
        runCurrent()
        assertTrue("still failing: the error state stays, nothing else to show", holder.state.value is MapUiState.Error)

        api.getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        advanceTimeBy(30_000)
        runCurrent()

        assertTrue("the periodic retry recovered the screen", holder.state.value is MapUiState.Content)
    }

    @Test
    fun `an explicit Refresh whose request fails still reports its own failure, even over existing data`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        assertTrue(holder.state.value is MapUiState.Content)

        api.getLatestLocationsResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        holder.refresh()

        assertTrue(holder.state.value is MapUiState.Error)
    }

    @Test
    fun `an explicit Refresh that arrives while a periodic fetch is in flight takes it over and reports its failure`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()

        val gate = CompletableDeferred<Unit>()
        api.getLatestLocationsGate = gate
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals("the timer fetch is held in flight", 2, api.getLatestLocationsCallCount)

        holder.refresh() // the user taps Refresh: not queued, not a third request...
        assertEquals(2, api.getLatestLocationsCallCount)
        api.getLatestLocationsResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        gate.complete(Unit)
        runCurrent()

        // ...but it owns the outcome: its failure is reported rather than swallowed as a silent tick.
        assertTrue(holder.state.value is MapUiState.Error)
    }

    @Test
    fun `a trigger arriving while a fetch is in flight is dropped - one request at a time`() = runTest {
        val api = FakeLocationsApi().apply { getLatestLocationsGate = CompletableDeferred() }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()
        assertEquals("the initial load is held in flight", 1, api.getLatestLocationsCallCount)

        advanceTimeBy(30_000)
        runCurrent()
        holder.onHidden()
        holder.onVisible()
        runCurrent()

        assertEquals("tick and foreground return both dropped", 1, api.getLatestLocationsCallCount)
    }

    @Test
    fun `periodic refreshes never move the camera and never drop the selection`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(
                memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"),
                memberWithOneDevice("u2", "Noor", "d2", 52.0, 4.0, "2026-10-05T07:00:00Z"),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        holder.selectMember("u2")
        val before = holder.state.value as MapUiState.Content
        assertEquals("u2", before.selectedUserId)

        // Every member moves a long way - exactly the data that used to yank the camera.
        api.getLatestLocationsResult = roster(
            memberWithOneDevice("u1", "Eric", "d1", 60.0, 20.0, "2026-10-05T07:30:00Z"),
            memberWithOneDevice("u2", "Noor", "d2", 61.0, 21.0, "2026-10-05T07:30:00Z"),
        )
        advanceTimeBy(90_000) // three ticks
        runCurrent()

        assertEquals(4, api.getLatestLocationsCallCount)
        val after = holder.state.value as MapUiState.Content
        assertEquals("no refresh mints a camera command (010 §3.6/§3.4)", before.cameraCommand, after.cameraCommand)
        assertEquals("u2", after.selectedUserId)
        assertEquals(60.0, after.members.first { it.userId == "u1" }.devices.single().lat)
    }

    @Test
    fun `a member selected while a fetch is in flight survives it, and so does the camera command the selection minted`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(
                memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"),
                memberWithOneDevice("u2", "Noor", "d2", 52.0, 4.0, "2026-10-05T07:00:00Z"),
            )
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()

        val gate = CompletableDeferred<Unit>()
        api.getLatestLocationsGate = gate
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals("the periodic fetch is held in flight", 2, api.getLatestLocationsCallCount)

        holder.selectMember("u2") // the user taps a row while the request is out
        val selected = holder.state.value as MapUiState.Content
        assertEquals("u2", selected.selectedUserId)
        assertEquals(MapCameraTarget.Center(52.0, 4.0, MapCamera.SINGLE_POINT_ZOOM), selected.cameraCommand?.target)

        gate.complete(Unit)
        runCurrent()

        val after = holder.state.value as MapUiState.Content
        assertEquals("the refresh must not erase the selection made meanwhile", "u2", after.selectedUserId)
        assertEquals(
            "nor swap the selection's camera command for an older one (the renderer would replay it)",
            selected.cameraCommand,
            after.cameraCommand,
        )
    }

    @Test
    fun `a confirmed PROFILE_NOT_FOUND on a periodic refresh still routes to Onboarding`() = runTest {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = roster(memberWithOneDevice("u1", "Eric", "d1", 51.0, 3.0, "2026-10-05T07:00:00Z"))
        }
        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()

        api.getLatestLocationsResult = ApiResult.Failure(ApiError.ProfileNotFound("gone", "r_9"))
        advanceTimeBy(30_000)
        runCurrent()

        // 010 §2.1: a confirmed state change (the family vanished under an open map), not a
        // failed refresh - the dead-end routing rule applies to every load, whichever trigger.
        assertEquals(MapUiState.RouteToOnboarding(OnboardingVariant.ProfileLess), holder.state.value)
    }

    private fun memberWithOneDevice(
        userId: String,
        displayName: String,
        deviceId: String,
        lat: Double,
        lon: Double,
        recordedAt: String,
    ): LatestMemberDto = LatestMemberDto(userId = userId, displayName = displayName, devices = listOf(device(deviceId, lat, lon, recordedAt)))

    private fun device(deviceId: String, lat: Double, lon: Double, recordedAt: String): LatestDeviceDto = LatestDeviceDto(
        deviceId = deviceId,
        deviceName = "Device $deviceId",
        lat = lat,
        lon = lon,
        recordedAt = recordedAt,
        trackingEnabled = true,
        syncIntervalMinutes = 15,
        isStale = false,
    )
}
