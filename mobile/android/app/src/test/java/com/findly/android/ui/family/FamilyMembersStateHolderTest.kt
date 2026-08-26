package com.findly.android.ui.family

import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.CallerRoleDto
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.MemberDto
import com.findly.android.network.dto.UpdateMemberRequestDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** [FamilyMembersStateHolder] is pure Kotlin (specs/003-android-client.md §14) — extracted from
 * the retired `SettingsStateHolder`'s family/member half (devices moved to
 * [com.findly.android.ui.devices.DevicesStateHolder]). Parent-vs-member permission gating
 * (001-api-contract.md §3.5/§3.6) is enforced client-side before any network call. */
class FamilyMembersStateHolderTest {

    @Test
    fun `load populates familyName, myRole, and members`() = runTest {
        val familyApi = FakeFamilyApi()
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is FamilyMembersUiState.Content)
        state as FamilyMembersUiState.Content
        assertEquals("Wauters", state.familyName)
        assertEquals("parent", state.myRole)
        assertEquals(2, state.members.size)
    }

    @Test
    fun `getMyFamily failure unrelated to profile-family surfaces a retryable Error`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        }
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is FamilyMembersUiState.Error)
    }

    @Test
    fun `PROFILE_NOT_FOUND routes to Onboarding profile-less`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_2"))
        }
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is FamilyMembersUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as FamilyMembersUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `FAMILY_NOT_FOUND routes to Onboarding family-less`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_3"))
        }
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is FamilyMembersUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as FamilyMembersUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `a parent updating a member role succeeds`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            updateMemberResult = ApiResult.Success(
                MemberDto("uid-member", "parent", "Noor", "2026-07-02T00:00:00Z"),
                defaultFeatures(),
            )
        }
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        holder.updateMember("uid-member", role = "parent")

        val state = holder.state.value as FamilyMembersUiState.Content
        assertEquals("parent", state.members.single { it.userId == "uid-member" }.role)
        assertEquals(listOf("uid-member" to UpdateMemberRequestDto(role = "parent")), familyApi.updateMemberCalls)
    }

    @Test
    fun `a non-parent updating a member role is blocked client-side without a network call`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(
                FamilyMeResponseDto(
                    familyId = "fam_test",
                    familyName = "Wauters",
                    createdAt = "2026-07-01T00:00:00Z",
                    me = CallerRoleDto("uid-member", "member"),
                    members = listOf(MemberDto("uid-member", "member", "Noor", "2026-07-02T00:00:00Z")),
                ),
                features = defaultFeatures(),
            )
        }
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        holder.updateMember("uid-member", role = "parent")

        val state = holder.state.value as FamilyMembersUiState.Content
        assertEquals("Only a parent can do this", state.mutationError)
        assertEquals(0, familyApi.updateMemberCalls.size)
    }

    @Test
    fun `removeMember by a parent removes the member from the local roster`() = runTest {
        val holder = FamilyMembersStateHolder(FakeFamilyApi(), backgroundScope)
        runCurrent()

        holder.removeMember("uid-member")

        val state = holder.state.value as FamilyMembersUiState.Content
        assertEquals(listOf("uid-parent"), state.members.map { it.userId })
    }

    @Test
    fun `removeMember failure such as last-parent surfaces the user-facing mutationError, never raw server text`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            removeMemberResult = ApiResult.Failure(
                ApiError.ValidationFailed(
                    fields = null,
                    reason = "lastParent",
                    message = "raw debug text from server",
                    requestId = "r_9",
                ),
            )
        }
        val holder = FamilyMembersStateHolder(familyApi, backgroundScope)
        runCurrent()

        holder.removeMember("uid-parent")

        val state = holder.state.value as FamilyMembersUiState.Content
        assertEquals("A family must always have at least one parent.", state.mutationError)
        assertTrue(state.members.any { it.userId == "uid-parent" })
    }
}
