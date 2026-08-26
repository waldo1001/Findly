package com.findly.android.ui.groups

import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.fakes.sampleGroupDetailDto
import com.findly.android.fakes.sampleGroupDto
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupMemberDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GroupDetailStateHolder] is pure Kotlin — mirrors
 * [com.findly.android.ui.family.FamilyMembersStateHolder]'s "gated mutation" shape: every
 * owner-only action is checked client-side before any network call (001-api-contract.md §12.4/
 * §12.5/§12.7/§12.9's role requirement is server-enforced regardless — defense in depth). */
class GroupDetailStateHolderTest {

    private val groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz"

    @Test
    fun `initial load populates Content from getGroup`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is GroupDetailUiState.Content)
        state as GroupDetailUiState.Content
        assertEquals("Festival crew", state.name)
        assertTrue(state.isOwner)
        assertEquals(listOf(groupId), api.getGroupCalls)
    }

    @Test
    fun `GROUP_EXPIRED surfaces as Expired, not a generic Error`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Failure(ApiError.GroupExpired("raw debug text", "r_1"))
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is GroupDetailUiState.Expired)
    }

    @Test
    fun `a non-owner rename attempt is rejected client-side without a network call`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "member"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.rename("New name")

        assertEquals("Only the group owner can do that.", (holder.state.value as GroupDetailUiState.Content).mutationError)
        assertTrue(api.updateGroupCalls.isEmpty())
    }

    @Test
    fun `owner rename succeeds and updates name`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
            updateGroupResult = ApiResult.Success(sampleGroupDto().copy(name = "Festival crew 2026"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.rename("Festival crew 2026")

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals("Festival crew 2026", state.name)
        assertEquals(false, state.isMutating)
        assertNull(state.mutationError)
    }

    @Test
    fun `owner rotateCode replaces the code`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.rotateCode()

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals("9XPT4WKA", state.code)
        assertEquals(listOf(groupId), api.rotateGroupCodeCalls)
    }

    @Test
    fun `owner kickMember removes the member from the roster and decrements memberCount`() = runTest {
        val members = listOf(
            GroupMemberDto("u1", "Eric", "owner", "2026-07-21T10:00:00Z"),
            GroupMemberDto("u9", "Noor", "member", "2026-07-21T10:05:00Z"),
        )
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(
                sampleGroupDetailDto(role = "owner", members = members).copy(memberCount = 2),
                features = groupsFeatures(),
            )
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.kickMember("u9")

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals(listOf("u1"), state.members?.map { it.userId })
        assertEquals(1, state.memberCount)
        assertEquals(listOf(groupId to "u9"), api.removeGroupMemberCalls)
    }

    @Test
    fun `owner deleteGroup marks left true on success`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.deleteGroup()

        assertTrue((holder.state.value as GroupDetailUiState.Content).left)
        assertEquals(listOf(groupId), api.deleteGroupCalls)
    }

    @Test
    fun `member leaveGroup marks left true on success`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "member"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.leaveGroup()

        assertTrue((holder.state.value as GroupDetailUiState.Content).left)
        assertEquals(listOf(groupId), api.leaveGroupCalls)
    }

    @Test
    fun `owner leaveGroup is rejected client-side (ownerCannotLeave) without a network call`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.leaveGroup()

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals("As the group owner, you can't leave — end or delete the group instead.", state.mutationError)
        assertTrue(api.leaveGroupCalls.isEmpty())
    }

    @Test
    fun `a mutation failure surfaces the user-facing message, never raw server text`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
            updateGroupResult = ApiResult.Failure(ApiError.GroupExpired("raw debug text", "r_1"))
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.rename("New name")

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals("This group has ended.", state.mutationError)
        assertEquals(false, state.isMutating)
    }
}
