package com.findly.android.ui.groups

import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupLatestLocationsResponseDto
import com.findly.android.network.dto.GroupMemberLocationDto
import com.findly.android.network.dto.GroupPositionDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
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
}
