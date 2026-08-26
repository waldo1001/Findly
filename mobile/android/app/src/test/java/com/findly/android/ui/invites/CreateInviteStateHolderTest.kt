package com.findly.android.ui.invites

import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.CreateInviteResponseDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [CreateInviteStateHolder] is pure Kotlin — tested with [FakeFamilyApi] (specs/003-android-
 * client.md §14, §16). Split out of the retired `InvitesStateHolder` (specs/010-app-shell-and-
 * screen-ux.md §5.1/§6: "Android's combined Invites screen splits into create + accept").
 */
class CreateInviteStateHolderTest {

    @Test
    fun `createInvite success populates createdInvite and clears the loading flag`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Success(
                CreateInviteResponseDto("7F3K9QRZ", "member", "2026-07-22T10:00:00Z"),
                defaultFeatures(),
            )
        }
        val holder = CreateInviteStateHolder(api)

        holder.createInvite(role = "member", emailHint = "kid@example.com")

        val state = holder.state.value
        assertEquals("7F3K9QRZ", state.createdInvite?.inviteCode)
        assertEquals("2026-07-22T10:00:00Z", state.createdInvite?.expiresAt)
        assertEquals(false, state.isCreatingInvite)
        assertNull(state.createInviteError)
        assertEquals(listOf("member" to "kid@example.com"), api.createInviteCalls)
    }

    @Test
    fun `createInvite failure (non-parent) surfaces the user-facing message, never raw server text`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Failure(ApiError.AuthForbidden("raw debug text from server", "r_1"))
        }
        val holder = CreateInviteStateHolder(api)

        holder.createInvite(role = "member")

        val state = holder.state.value
        assertEquals("You don't have permission to do that.", state.createInviteError)
        assertNull(state.createdInvite)
        assertEquals(false, state.isCreatingInvite)
    }

    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule does NOT apply to createInvite:
    // POST /families/me/invites is a mutation, and §2.1 is explicit that mutation/action failures
    // "keep their existing inline error rendering — this rule is about the load path." (Carried
    // over unchanged from the retired InvitesStateHolder's own reverted review finding.)

    @Test
    fun `createInvite PROFILE_NOT_FOUND renders inline (createInvite is a mutation, not a load path)`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_10"))
        }
        val holder = CreateInviteStateHolder(api)

        holder.createInvite(role = "member")

        val state = holder.state.value
        assertEquals("We couldn't find your profile.", state.createInviteError)
        assertNull(state.createdInvite)
    }

    @Test
    fun `createInvite FAMILY_NOT_FOUND renders inline (createInvite is a mutation, not a load path)`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_11"))
        }
        val holder = CreateInviteStateHolder(api)

        holder.createInvite(role = "member")

        val state = holder.state.value
        assertEquals("We couldn't find your family. Please try again.", state.createInviteError)
        assertNull(state.createdInvite)
    }

    @Test
    fun `reset clears createdInvite and any error, enabling 'Create another' (010 §5_1 bullet 6)`() = runTest {
        val api = FakeFamilyApi().apply {
            createInviteResult = ApiResult.Success(
                CreateInviteResponseDto("7F3K9QRZ", "member", "2026-07-22T10:00:00Z"),
                defaultFeatures(),
            )
        }
        val holder = CreateInviteStateHolder(api)
        holder.createInvite(role = "member")
        assertEquals("7F3K9QRZ", holder.state.value.createdInvite?.inviteCode)

        holder.reset()

        val state = holder.state.value
        assertNull(state.createdInvite)
        assertNull(state.createInviteError)
        assertEquals(false, state.isCreatingInvite)
    }
}
