package com.findly.android.ui.groups

import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupLatestLocationsResponseDto
import com.findly.android.network.dto.GroupMemberLocationDto
import com.findly.android.network.dto.GroupPositionDto
import com.findly.android.ui.map.MapCamera
import com.findly.android.ui.map.MapCameraTarget
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GroupMapStateHolder] mirrors [com.findly.android.ui.map.MapStateHolder]'s shape exactly
 * (specs/003-android-client.md §12.2 — "polls ... the same way `MapStateHolder` treats the family
 * map"): an eager `init` load plus a public [GroupMapStateHolder.refresh] for pull-to-refresh. */
class GroupMapStateHolderTest {

    private val groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz"

    @Test
    fun `initial load populates the roster from getGroupLatestLocations, position-only`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(
                    members = listOf(
                        GroupMemberLocationDto(
                            userId = "u1",
                            displayName = "Eric",
                            role = "owner",
                            location = GroupPositionDto(
                                lat = 51.0543,
                                lon = 3.7174,
                                accuracyM = 15.0,
                                recordedAt = "2026-07-21T09:58:00Z",
                                receivedAt = "2026-07-21T09:58:02Z",
                                isStale = false,
                            ),
                        ),
                        GroupMemberLocationDto(userId = "u9", displayName = "Noor", role = "member", location = null),
                    ),
                ),
                features = groupsFeatures(),
            )
        }

        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is GroupMapUiState.Content)
        state as GroupMapUiState.Content
        assertEquals(2, state.members.size)
        val eric = state.members.first { it.userId == "u1" }
        assertEquals(51.0543, eric.lat)
        assertTrue(eric.hasLocation)
        assertEquals(false, eric.isStale)
        val noor = state.members.first { it.userId == "u9" }
        assertEquals(false, noor.hasLocation)
        assertEquals(listOf(groupId), api.getGroupLatestLocationsCalls)
    }

    @Test
    fun `GROUP_EXPIRED surfaces as Expired, not a generic Error`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Failure(ApiError.GroupExpired("raw debug text", "r_1"))
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is GroupMapUiState.Expired)
    }

    @Test
    fun `a non-expiry failure surfaces the user-facing message, never raw server text`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Failure(ApiError.GroupNotFound("raw debug text", "r_1"))
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is GroupMapUiState.Error)
        assertEquals("That group couldn't be found.", (state as GroupMapUiState.Error).message)
    }

    @Test
    fun `refresh re-fetches and replaces the roster`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult =
                ApiResult.Success(GroupLatestLocationsResponseDto(members = emptyList()), features = groupsFeatures())
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        assertEquals(1, api.getGroupLatestLocationsCalls.size)

        holder.refresh()

        assertEquals(2, api.getGroupLatestLocationsCalls.size)
        assertTrue(holder.state.value is GroupMapUiState.Content)
    }

    // specs/010-app-shell-and-screen-ux.md §3.2/§3.4/§3.5 — the group map shares the family map's
    // camera policy through the same renderer seam; position-only, so selection targets a
    // member's own point directly (no per-device freshest resolution needed).

    @Test
    fun `the first load with a located member emits a camera command`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 51.0543, 3.7174))),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()

        val state = holder.state.value as GroupMapUiState.Content
        assertEquals(MapCameraTarget.Center(51.0543, 3.7174, MapCamera.SINGLE_POINT_ZOOM), state.cameraCommand?.target)
    }

    @Test
    fun `a refresh that changes the point set never moves the camera again`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 51.0, 3.0))),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        val firstCommand = (holder.state.value as GroupMapUiState.Content).cameraCommand

        api.getGroupLatestLocationsResult = ApiResult.Success(
            GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 60.0, 20.0))),
            features = groupsFeatures(),
        )
        holder.refresh()

        val secondCommand = (holder.state.value as GroupMapUiState.Content).cameraCommand
        assertEquals(firstCommand, secondCommand)
    }

    @Test
    fun `selecting a located member zooms to their point at SINGLE_POINT_ZOOM`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 51.0, 3.0))),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        val beforeSeq = (holder.state.value as GroupMapUiState.Content).cameraCommand?.seq

        holder.selectMember("u1")

        val state = holder.state.value as GroupMapUiState.Content
        assertEquals("u1", state.selectedUserId)
        assertEquals(MapCameraTarget.Center(51.0, 3.0, MapCamera.SINGLE_POINT_ZOOM), state.cameraCommand?.target)
        assertNotEquals(beforeSeq, state.cameraCommand?.seq)
    }

    @Test
    fun `selecting a member with no location highlights without moving the camera`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(
                    members = listOf(GroupMemberLocationDto(userId = "u9", displayName = "Noor", role = "member", location = null)),
                ),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        val before = holder.state.value as GroupMapUiState.Content

        holder.selectMember("u9")

        val after = holder.state.value as GroupMapUiState.Content
        assertEquals("u9", after.selectedUserId)
        assertEquals(before.cameraCommand, after.cameraCommand)
    }

    @Test
    fun `selecting the already-selected member deselects it`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 51.0, 3.0))),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        holder.selectMember("u1")
        assertEquals("u1", (holder.state.value as GroupMapUiState.Content).selectedUserId)

        holder.selectMember("u1")

        assertNull((holder.state.value as GroupMapUiState.Content).selectedUserId)
    }

    @Test
    fun `deselect clears the selection without moving the camera`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 51.0, 3.0))),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        holder.selectMember("u1")
        val selected = holder.state.value as GroupMapUiState.Content

        holder.deselect()

        val deselected = holder.state.value as GroupMapUiState.Content
        assertNull(deselected.selectedUserId)
        assertEquals(selected.cameraCommand, deselected.cameraCommand)
    }

    @Test
    fun `fitAll re-runs the policy over current points on an explicit action`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Success(
                GroupLatestLocationsResponseDto(members = listOf(memberAt("u1", "Eric", 51.0, 3.0), memberAt("u2", "Noor", 60.0, 20.0))),
                features = groupsFeatures(),
            )
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        val before = (holder.state.value as GroupMapUiState.Content).cameraCommand

        holder.fitAll()

        val after = (holder.state.value as GroupMapUiState.Content).cameraCommand
        assertNotEquals(before?.seq, after?.seq)
        assertTrue(after?.target is MapCameraTarget.Bounds)
    }

    private fun memberAt(userId: String, displayName: String, lat: Double, lon: Double): GroupMemberLocationDto = GroupMemberLocationDto(
        userId = userId,
        displayName = displayName,
        role = "member",
        location = GroupPositionDto(
            lat = lat,
            lon = lon,
            accuracyM = 10.0,
            recordedAt = "2026-08-26T10:00:00Z",
            receivedAt = "2026-08-26T10:00:02Z",
            isStale = false,
        ),
    )
}
