package com.findly.android.ui.map

import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import com.findly.android.network.dto.LatestMemberDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
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
            getLatestLocationsResult = ApiResult.Failure(ApiError.FamilyNotFound("raw debug text from server", "r_1"))
        }

        val holder = MapStateHolder(api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is MapUiState.Error)
        assertEquals("We couldn't find your family. Please try again.", (state as MapUiState.Error).message)
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
}
