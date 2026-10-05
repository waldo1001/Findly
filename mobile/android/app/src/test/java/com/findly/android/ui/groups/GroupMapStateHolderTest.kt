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

/** [GroupMapStateHolder] mirrors [com.findly.android.ui.map.MapStateHolder]'s shape exactly
 * (specs/003-android-client.md §12.2 — "polls ... the same way `MapStateHolder` treats the family
 * map"): an eager `init` load plus a public [GroupMapStateHolder.refresh] for pull-to-refresh. */
@OptIn(ExperimentalCoroutinesApi::class)
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

    // specs/010-app-shell-and-screen-ux.md §3.6 (A55) — the group map follows the same freshness
    // rules through the same MapRefreshController (its own policy tests: MapRefreshControllerTest).

    private fun roster(vararg members: GroupMemberLocationDto) = ApiResult.Success(
        GroupLatestLocationsResponseDto(members = members.toList()),
        features = groupsFeatures(),
    )

    @Test
    fun `while visible the group roster is re-fetched every 30 s and never in the background`() = runTest {
        val api = FakeGroupsApi().apply { getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 51.0, 3.0)) }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        advanceTimeBy(5 * 60_000)
        runCurrent()
        assertEquals("never visible: only the initial load", 1, api.getGroupLatestLocationsCalls.size)

        holder.onVisible()
        runCurrent()
        assertEquals("first appearance fetches once", 1, api.getGroupLatestLocationsCalls.size)

        api.getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 52.0, 4.0))
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(2, api.getGroupLatestLocationsCalls.size)
        assertEquals(52.0, (holder.state.value as GroupMapUiState.Content).members.single().lat)

        holder.onHidden()
        advanceTimeBy(5 * 60_000)
        runCurrent()
        assertEquals("hidden: no timer", 2, api.getGroupLatestLocationsCalls.size)

        holder.onVisible()
        runCurrent()
        assertEquals("a foreground return re-fetches", 3, api.getGroupLatestLocationsCalls.size)
    }

    @Test
    fun `a failed periodic refresh keeps the last group roster with no error, a failed first load shows the error`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        assertTrue("a first-load failure shows the error state", holder.state.value is GroupMapUiState.Error)
        holder.onVisible()
        runCurrent()

        api.getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 51.0, 3.0))
        advanceTimeBy(30_000)
        runCurrent()
        val loaded = holder.state.value
        assertTrue("a periodic success recovers the screen", loaded is GroupMapUiState.Content)

        api.getGroupLatestLocationsResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        advanceTimeBy(30_000)
        runCurrent()

        assertEquals("a failed periodic refresh surfaces nothing", loaded, holder.state.value)
    }

    @Test
    fun `an explicit Refresh failure still reports itself over existing group data`() = runTest {
        val api = FakeGroupsApi().apply { getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 51.0, 3.0)) }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()

        api.getGroupLatestLocationsResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        holder.refresh()

        assertTrue(holder.state.value is GroupMapUiState.Error)
    }

    @Test
    fun `GROUP_EXPIRED on a periodic refresh still surfaces as Expired - it is a terminal state, not a failed refresh`() = runTest {
        val api = FakeGroupsApi().apply { getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 51.0, 3.0)) }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()

        api.getGroupLatestLocationsResult = ApiResult.Failure(ApiError.GroupExpired("ended", "r_1"))
        advanceTimeBy(30_000)
        runCurrent()

        assertTrue(holder.state.value is GroupMapUiState.Expired)
    }

    @Test
    fun `periodic refreshes never move the group camera or drop the selection, even one selected mid-fetch`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 51.0, 3.0), memberAt("u2", "Noor", 52.0, 4.0))
        }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        holder.onVisible()
        runCurrent()
        val firstLoad = holder.state.value as GroupMapUiState.Content

        api.getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 60.0, 20.0), memberAt("u2", "Noor", 61.0, 21.0))
        advanceTimeBy(30_000)
        runCurrent()
        val afterTick = holder.state.value as GroupMapUiState.Content
        assertEquals("a tick mints no camera command", firstLoad.cameraCommand, afterTick.cameraCommand)
        assertEquals(60.0, afterTick.members.first { it.userId == "u1" }.lat)

        val gate = CompletableDeferred<Unit>()
        api.getGroupLatestLocationsGate = gate
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals("the next tick's fetch is held in flight", 3, api.getGroupLatestLocationsCalls.size)

        holder.selectMember("u2") // tapped while the request is out
        val selected = holder.state.value as GroupMapUiState.Content
        gate.complete(Unit)
        runCurrent()

        val after = holder.state.value as GroupMapUiState.Content
        assertEquals("u2", after.selectedUserId)
        assertEquals(selected.cameraCommand, after.cameraCommand)
    }

    @Test
    fun `an exception that escapes the API client is a failed refresh - silent on a periodic one, the error state on the first load`() = runTest {
        val api = FakeGroupsApi().apply { getGroupLatestLocationsThrowable = IllegalStateException("malformed body") }
        val holder = GroupMapStateHolder(groupId, api, backgroundScope)
        runCurrent()
        assertTrue("first load: error state, not a crash", holder.state.value is GroupMapUiState.Error)

        api.getGroupLatestLocationsThrowable = null
        api.getGroupLatestLocationsResult = roster(memberAt("u1", "Eric", 51.0, 3.0))
        holder.onVisible()
        advanceTimeBy(30_000)
        runCurrent()
        val loaded = holder.state.value
        assertTrue(loaded is GroupMapUiState.Content)

        api.getGroupLatestLocationsThrowable = IllegalStateException("malformed body")
        advanceTimeBy(30_000)
        runCurrent() // an uncaught exception on backgroundScope would fail the test right here

        assertEquals("periodic: last roster kept, nothing surfaced", loaded, holder.state.value)
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
