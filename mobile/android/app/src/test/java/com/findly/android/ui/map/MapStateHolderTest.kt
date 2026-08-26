package com.findly.android.ui.map

import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import com.findly.android.network.dto.LatestMemberDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [MapStateHolder] is pure Kotlin (specs/003-android-client.md §14) — tested with a
 * `backgroundScope` + [FakeLocationsApi], no Robolectric/emulator (001-api-contract.md §5.2). */
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
