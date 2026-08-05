package com.findly.android.ui.invites

import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.AcceptInviteResponseDto
import com.findly.android.network.dto.CreateInviteResponseDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [InvitesStateHolder] is pure Kotlin — tested with [FakeFamilyApi]
 * (specs/003-android-client.md §14, §16). */
class InvitesStateHolderTest {

    @Test
    fun `createInvite success populates createdInvite and clears the loading flag`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Success(
                CreateInviteResponseDto("7F3K9QRZ", "member", "2026-07-22T10:00:00Z"),
                defaultFeatures(),
            )
        }
        val holder = InvitesStateHolder(api)

        holder.createInvite(role = "member", emailHint = "kid@example.com")

        val state = holder.state.value
        assertEquals("7F3K9QRZ", state.createdInvite?.inviteCode)
        assertEquals(false, state.isCreatingInvite)
        assertNull(state.createInviteError)
        assertEquals(listOf("member" to "kid@example.com"), api.createInviteCalls)
    }

    @Test
    fun `createInvite failure (non-parent) surfaces the user-facing message, never raw server text`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Failure(ApiError.AuthForbidden("raw debug text from server", "r_1"))
        }
        val holder = InvitesStateHolder(api)

        holder.createInvite(role = "member")

        val state = holder.state.value
        assertEquals("You don't have permission to do that.", state.createInviteError)
        assertNull(state.createdInvite)
        assertEquals(false, state.isCreatingInvite)
    }

    @Test
    fun `acceptInvite success populates acceptedFamily`() = runTest {
        val api = FakeFamilyApi().apply {
            acceptInviteResult = ApiResult.Success(
                AcceptInviteResponseDto("fam_test", "Wauters", "member"),
                defaultFeatures(),
            )
        }
        val holder = InvitesStateHolder(api)

        holder.acceptInvite(inviteCode = "7F3K9QRZ", displayName = "Noor")

        val state = holder.state.value
        assertEquals("Wauters", state.acceptedFamily?.familyName)
        assertEquals(false, state.isAcceptingInvite)
        assertNull(state.acceptInviteError)
        assertEquals(listOf("7F3K9QRZ" to "Noor"), api.acceptInviteCalls)
    }

    @Test
    fun `acceptInvite with a blank display name surfaces a validation message and never reaches the network`() = runTest {
        val api = FakeFamilyApi()
        val holder = InvitesStateHolder(api)

        holder.acceptInvite(inviteCode = "7F3K9QRZ", displayName = "  ")

        val state = holder.state.value
        assertEquals("Enter a display name", state.acceptInviteError)
        assertEquals(false, state.isAcceptingInvite)
        assertNull(state.acceptedFamily)
        assertTrue(api.acceptInviteCalls.isEmpty())
    }

    @Test
    fun `acceptInvite surfaces each catalog error as its distinct user-facing message`() = runTest {
        val api = FakeFamilyApi()
        val holder = InvitesStateHolder(api)

        api.acceptInviteResult = ApiResult.Failure(ApiError.InviteInvalid("raw debug text from server", "r_1"))
        holder.acceptInvite("BADCODE1", "Noor")
        assertEquals("That invite code isn't valid.", holder.state.value.acceptInviteError)

        api.acceptInviteResult = ApiResult.Failure(ApiError.InviteAlreadyUsed("raw debug text from server", "r_2"))
        holder.acceptInvite("USEDCODE", "Noor")
        assertEquals("That invite code has already been used.", holder.state.value.acceptInviteError)

        api.acceptInviteResult = ApiResult.Failure(ApiError.InviteExpired("raw debug text from server", "r_3"))
        holder.acceptInvite("OLDCODE1", "Noor")
        assertEquals("This invite code has expired.", holder.state.value.acceptInviteError)

        api.acceptInviteResult = ApiResult.Failure(ApiError.FamilyAlreadyMember("raw debug text from server", "r_4"))
        holder.acceptInvite("ANYCODE1", "Noor")
        assertEquals("You're already part of a family.", holder.state.value.acceptInviteError)
    }

    @Test
    fun `create and accept flows are independent`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Failure(ApiError.AuthForbidden("raw debug text from server", "r_1"))
            acceptInviteResult = ApiResult.Success(AcceptInviteResponseDto("fam_test", "Wauters", "member"), defaultFeatures())
        }
        val holder = InvitesStateHolder(api)

        holder.createInvite(role = "member")
        holder.acceptInvite("CODE1234", "Noor")

        val state = holder.state.value
        assertEquals("You don't have permission to do that.", state.createInviteError)
        assertEquals("Wauters", state.acceptedFamily?.familyName)
    }
}
