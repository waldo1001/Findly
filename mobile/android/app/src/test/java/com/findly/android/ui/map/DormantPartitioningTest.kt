package com.findly.android.ui.map

import com.findly.android.fakes.FakeLocationsApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import com.findly.android.network.dto.LatestMemberDto
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A61 — specs/011 §2 / 010 §3.3: dormant devices get no marker, no roster chip, take no part in
 * the camera fit or the freshest-device choice; an all-dormant member reads `No recent location`
 * but stays selectable. */
@OptIn(ExperimentalCoroutinesApi::class)
class DormantPartitioningTest {

    private fun dto(id: String, lat: Double, lon: Double, recordedAt: String, dormant: Boolean) = LatestDeviceDto(
        deviceId = id,
        deviceName = "D$id",
        lat = lat,
        lon = lon,
        recordedAt = recordedAt,
        trackingEnabled = true,
        syncIntervalMinutes = 15,
        isStale = false,
        isDormant = dormant,
    )

    private fun device(id: String, recordedAt: String?, dormant: Boolean) = RosterDeviceUi(
        deviceId = id,
        deviceName = "D$id",
        lat = 51.0,
        lon = 3.7,
        recordedAt = recordedAt,
        batteryPct = null,
        trackingEnabled = true,
        syncIntervalMinutes = 15,
        isStale = false,
        isDormant = dormant,
    )

    private fun TestScope.holderFor(vararg members: LatestMemberDto): MapStateHolder {
        val api = FakeLocationsApi().apply {
            getLatestLocationsResult = ApiResult.Success(LatestLocationsResponseDto(members.toList()), defaultFeatures())
        }
        return MapStateHolder(api, backgroundScope).also { runCurrent() }
    }

    private val activeEric = LatestMemberDto("u1", "Eric", listOf(dto("a", 51.0, 3.0, "2026-07-19T09:00:00Z", dormant = false)))
    private val dormantNoor = LatestMemberDto("u2", "Noor", listOf(dto("b", 10.0, 100.0, "2026-07-19T09:00:00Z", dormant = true)))

    @Test
    fun `isDormant is carried from the wire into the roster device`() = runTest {
        val holder = holderFor(dormantNoor)
        val state = holder.state.value as MapUiState.Content
        assertTrue(state.members.single().devices.single().isDormant)
    }

    @Test
    fun `the initial camera fit ignores dormant devices`() = runTest {
        val holder = holderFor(activeEric, dormantNoor)
        val command = (holder.state.value as MapUiState.Content).cameraCommand!!
        assertEquals(MapCameraTarget.Center(51.0, 3.0, MapCamera.SINGLE_POINT_ZOOM), command.target)
    }

    @Test
    fun `fit-all ignores dormant devices`() = runTest {
        val holder = holderFor(activeEric, dormantNoor)
        holder.fitAll()
        val target = (holder.state.value as MapUiState.Content).cameraCommand!!.target
        assertTrue(target is MapCameraTarget.Center)
    }

    @Test
    fun `freshest device choice skips a newer dormant device`() {
        val result = MapCameraPolicy.freshestLocatedDevice(
            listOf(
                device("old-active", "2026-07-01T09:00:00Z", dormant = false),
                device("new-dormant", "2026-07-19T09:00:00Z", dormant = true),
            ),
        )
        assertEquals("old-active", result?.deviceId)
    }

    @Test
    fun `selecting an all-dormant member selects it without moving the camera`() = runTest {
        val holder = holderFor(activeEric, dormantNoor)
        val before = (holder.state.value as MapUiState.Content).cameraCommand
        holder.selectMember("u2")
        val after = holder.state.value as MapUiState.Content
        assertEquals("u2", after.selectedUserId)
        assertEquals(before, after.cameraCommand)
    }

    @Test
    fun `shownDevices excludes dormant and hasOnlyDormantDevices is true only when every device is dormant`() {
        val mixed = RosterMemberUi("u", "N", listOf(device("a", null, dormant = false), device("b", null, dormant = true)))
        val onlyDormant = RosterMemberUi("u", "N", listOf(device("b", null, dormant = true)))
        val none = RosterMemberUi("u", "N", emptyList())

        assertEquals(listOf("a"), mixed.shownDevices.map { it.deviceId })
        assertFalse(mixed.hasOnlyDormantDevices)
        assertTrue(onlyDormant.hasOnlyDormantDevices)
        assertTrue(onlyDormant.shownDevices.isEmpty())
        assertFalse(none.hasOnlyDormantDevices) // "No devices registered" stays its own state
    }

    @Test
    fun `all-dormant member row text is No recent location`() {
        assertEquals("No recent location", RosterRowText.memberWithoutShownDevices(hasOnlyDormantDevices = true))
        assertEquals("No devices registered", RosterRowText.memberWithoutShownDevices(hasOnlyDormantDevices = false))
    }
}
