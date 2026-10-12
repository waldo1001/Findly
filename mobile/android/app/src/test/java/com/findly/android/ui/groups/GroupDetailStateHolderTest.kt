package com.findly.android.ui.groups

import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.fakes.sampleGroupDetailDto
import com.findly.android.fakes.sampleGroupDto
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupMemberDto
import com.findly.android.network.dto.UpdateGroupRequestDto
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

    // ------------------------------------------------------------------
    // 005 §2.5 — groups without an end date (A66)
    // ------------------------------------------------------------------

    @Test
    fun `a group with endsAt null loads as Content without crashing`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(endsAt = null), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        val state = holder.state.value as GroupDetailUiState.Content
        assertNull(state.endsAt)
        assertEquals(false, state.canRemoveEndDate)
    }

    @Test
    fun `canRemoveEndDate is true only for an owner on a dated active or ended group`() = runTest {
        suspend fun contentFor(role: String, endsAt: String?, state: String): GroupDetailUiState.Content {
            val api = FakeGroupsApi().apply {
                getGroupResult = ApiResult.Success(
                    sampleGroupDetailDto(role = role, endsAt = endsAt, state = state),
                    features = groupsFeatures(),
                )
            }
            val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
            runCurrent()
            return holder.state.value as GroupDetailUiState.Content
        }

        assertTrue(contentFor("owner", "2026-08-02T22:00:00Z", "active").canRemoveEndDate)
        assertTrue(contentFor("owner", "2026-07-20T22:00:00Z", "ended").canRemoveEndDate)
        assertEquals(false, contentFor("owner", "2026-07-20T22:00:00Z", "archived").canRemoveEndDate)
        assertEquals(false, contentFor("member", "2026-08-02T22:00:00Z", "active").canRemoveEndDate)
        assertEquals(false, contentFor("owner", null, "active").canRemoveEndDate)
    }

    @Test
    fun `owner removeEndDate PATCHes endsAt null and the state shows no end date`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures())
            updateGroupResult = ApiResult.Success(sampleGroupDto(endsAt = null), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.removeEndDate()

        val call = api.updateGroupCalls.single()
        assertEquals(groupId, call.first)
        assertEquals(UpdateGroupRequestDto.removeEndDate(), call.second)
        val state = holder.state.value as GroupDetailUiState.Content
        assertNull(state.endsAt)
        assertEquals(false, state.isMutating)
    }

    @Test
    fun `removeEndDate reactivates an ended group`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(
                sampleGroupDetailDto(role = "owner", endsAt = "2026-07-20T22:00:00Z", state = "ended"),
                features = groupsFeatures(),
            )
            updateGroupResult = ApiResult.Success(sampleGroupDto(endsAt = null, state = "active"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.removeEndDate()

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals("active", state.state)
        assertNull(state.endsAt)
    }

    @Test
    fun `removeEndDate by a non-owner gets the standard not-owner error and makes no call`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "member"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.removeEndDate()

        assertEquals("Only the group owner can do that.", (holder.state.value as GroupDetailUiState.Content).mutationError)
        assertTrue(api.updateGroupCalls.isEmpty())
    }

    @Test
    fun `removeEndDate is a no-op for a non-owner, an already-undated group and an archived group`() = runTest {
        suspend fun callsFor(role: String, endsAt: String?, state: String): Int {
            val api = FakeGroupsApi().apply {
                getGroupResult = ApiResult.Success(
                    sampleGroupDetailDto(role = role, endsAt = endsAt, state = state),
                    features = groupsFeatures(),
                )
            }
            val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
            runCurrent()
            holder.removeEndDate()
            return api.updateGroupCalls.size
        }

        assertEquals(0, callsFor("member", "2026-08-02T22:00:00Z", "active"))
        assertEquals(0, callsFor("owner", null, "active"))
        assertEquals(0, callsFor("owner", "2026-07-20T22:00:00Z", "archived"))
    }

    @Test
    fun `removeEndDate refused by the maxOwnedGroups cap names the limit`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(
                sampleGroupDetailDto(role = "owner", endsAt = "2026-07-20T22:00:00Z", state = "ended"),
                features = groupsFeatures(),
            )
            updateGroupResult = ApiResult.Failure(ApiError.LimitExceeded("maxOwnedGroups", "raw", "r_1"))
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.removeEndDate()

        val state = holder.state.value as GroupDetailUiState.Content
        assertEquals(
            "You already have the maximum number of active groups you created. End or delete one first.",
            state.mutationError,
        )
        assertEquals("2026-07-20T22:00:00Z", state.endsAt)
    }

    @Test
    fun `updateEndsAt works from a no-end group (Set an end date)`() = runTest {
        val api = FakeGroupsApi().apply {
            getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner", endsAt = null), features = groupsFeatures())
            updateGroupResult = ApiResult.Success(sampleGroupDto(endsAt = "2026-09-01T10:00:00Z"), features = groupsFeatures())
        }
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope)
        runCurrent()

        holder.updateEndsAt("2026-09-01T10:00:00Z")

        assertEquals(UpdateGroupRequestDto.setEndsAt("2026-09-01T10:00:00Z"), api.updateGroupCalls.single().second)
        assertEquals("2026-09-01T10:00:00Z", (holder.state.value as GroupDetailUiState.Content).endsAt)
    }

    // ------------------------------------------------------------------
    // A66 review: setEndDate is bounded like the create screen (005 §2.5 item 6)
    // ------------------------------------------------------------------

    private val nowMillis = 1_784_707_200_000L // 2026-07-21T10:00:00Z
    private val hour = 60L * 60 * 1000
    private val day = 24 * hour

    private suspend fun kotlinx.coroutines.test.TestScope.ownerHolder(
        maxDays: Int?,
        api: FakeGroupsApi = FakeGroupsApi(),
    ): Pair<GroupDetailStateHolder, FakeGroupsApi> {
        api.getGroupResult = ApiResult.Success(sampleGroupDetailDto(role = "owner"), features = groupsFeatures(maxGroupDurationDays = maxDays))
        val holder = GroupDetailStateHolder(groupId, api, backgroundScope, clock = { nowMillis })
        runCurrent()
        return holder to api
    }

    @Test
    fun `Content carries maxGroupDurationDays from the envelope limits`() = runTest {
        val (holder, _) = ownerHolder(maxDays = 30)
        assertEquals(30, (holder.state.value as GroupDetailUiState.Content).maxGroupDurationDays)
        val (holder2, _) = ownerHolder(maxDays = null)
        assertNull((holder2.state.value as GroupDetailUiState.Content).maxGroupDurationDays)
    }

    @Test
    fun `setEndDate below the 1h floor sets mutationError and makes no call`() = runTest {
        val (holder, api) = ownerHolder(maxDays = 30)

        holder.setEndDate(nowMillis + 30 * 60_000)

        assertEquals(
            "End time must be at least 1 hour from now",
            (holder.state.value as GroupDetailUiState.Content).mutationError,
        )
        assertTrue(api.updateGroupCalls.isEmpty())
    }

    @Test
    fun `setEndDate above the plan cap sets mutationError and makes no call`() = runTest {
        val (holder, api) = ownerHolder(maxDays = 30)

        holder.setEndDate(nowMillis + 31 * day)

        assertEquals(
            "That end date is further out than your plan allows",
            (holder.state.value as GroupDetailUiState.Content).mutationError,
        )
        assertTrue(api.updateGroupCalls.isEmpty())
    }

    @Test
    fun `setEndDate with a null cap accepts one year out and PATCHes the ISO instant`() = runTest {
        val (holder, api) = ownerHolder(maxDays = null)

        holder.setEndDate(nowMillis + 365 * day)

        val sent = api.updateGroupCalls.single().second
        assertEquals(UpdateGroupRequestDto.setEndsAt(java.time.Instant.ofEpochMilli(nowMillis + 365 * day).toString()), sent)
    }

    @Test
    fun `updateEndsAt has no floor - End group now sends now plus 60s`() = runTest {
        val (holder, api) = ownerHolder(maxDays = 30)

        holder.updateEndsAt(java.time.Instant.ofEpochMilli(nowMillis + 60_000).toString())

        assertEquals(1, api.updateGroupCalls.size)
    }
}
