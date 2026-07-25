package com.findly.android.ui.groups

import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.fakes.sampleGroupDto
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.ListGroupsResponseDto
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GroupsListStateHolder] is pure Kotlin (specs/003-android-client.md §14) — tested with a
 * `backgroundScope` + [FakeGroupsApi]/[FakeFamilyApi], mirroring [com.findly.android.ui.map.MapStateHolderTest]. */
class GroupsListStateHolderTest {

    @Test
    fun `initial load populates the roster and marks hasFamily true on a successful family fetch`() = runTest {
        val groupsApi = FakeGroupsApi().apply {
            listGroupsResult = ApiResult.Success(
                ListGroupsResponseDto(groups = listOf(sampleGroupDto())),
                features = groupsFeatures(),
            )
        }
        val familyApi = FakeFamilyApi() // default getMyFamilyResult is a Success

        val holder = GroupsListStateHolder(groupsApi, familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is GroupsListUiState.Content)
        state as GroupsListUiState.Content
        assertEquals(1, state.groups.size)
        assertEquals("Festival crew", state.groups.single().name)
        assertTrue(state.hasFamily)
        assertFalse(state.needsDisplayName)
        assertEquals(5, state.limits?.maxActiveGroups)
    }

    @Test
    fun `FAMILY_NOT_FOUND on the family probe marks hasFamily false, needsDisplayName false`() = runTest {
        val groupsApi = FakeGroupsApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_1"))
        }

        val holder = GroupsListStateHolder(groupsApi, familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value as GroupsListUiState.Content
        assertFalse(state.hasFamily)
        assertFalse(state.needsDisplayName)
    }

    @Test
    fun `PROFILE_NOT_FOUND on the family probe marks hasFamily false, needsDisplayName true`() = runTest {
        val groupsApi = FakeGroupsApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }

        val holder = GroupsListStateHolder(groupsApi, familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value as GroupsListUiState.Content
        assertFalse(state.hasFamily)
        assertTrue(state.needsDisplayName)
    }

    @Test
    fun `an unrelated family-probe failure defaults hasFamily true rather than mislabeling the user`() = runTest {
        val groupsApi = FakeGroupsApi()
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }

        val holder = GroupsListStateHolder(groupsApi, familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value as GroupsListUiState.Content
        assertTrue(state.hasFamily)
        assertFalse(state.needsDisplayName)
    }

    @Test
    fun `a listGroups failure surfaces the user-facing message, never the raw server message`() = runTest {
        val groupsApi = FakeGroupsApi().apply {
            listGroupsResult = ApiResult.Failure(ApiError.ProfileNotFound("raw debug text", "r_1"))
        }
        val familyApi = FakeFamilyApi()

        val holder = GroupsListStateHolder(groupsApi, familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is GroupsListUiState.Error)
        assertEquals("We couldn't find your profile. Please try again.", (state as GroupsListUiState.Error).message)
    }

    @Test
    fun `refresh re-fetches and replaces the list`() = runTest {
        val groupsApi = FakeGroupsApi().apply {
            listGroupsResult = ApiResult.Success(ListGroupsResponseDto(groups = emptyList()), features = groupsFeatures())
        }
        val familyApi = FakeFamilyApi()
        val holder = GroupsListStateHolder(groupsApi, familyApi, backgroundScope)
        runCurrent()
        assertEquals(1, groupsApi.listGroupsCallCount)

        holder.refresh()

        assertEquals(2, groupsApi.listGroupsCallCount)
        assertTrue(holder.state.value is GroupsListUiState.Content)
    }
}
