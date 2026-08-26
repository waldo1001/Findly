package com.findly.android.ui.onboarding

import com.findly.android.network.ApiError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** [ProfileDeadEndRouting] is pure Kotlin — the 010-app-shell-and-screen-ux.md §2.1 routing rule,
 * table-driven over every catalog code that matters plus the family-scoped/not distinction. */
class ProfileDeadEndRoutingTest {

    @Test
    fun `PROFILE_NOT_FOUND always routes profile-less, family-scoped or not`() {
        val error = ApiError.ProfileNotFound("no profile", "r_1")
        assertEquals(OnboardingVariant.ProfileLess, ProfileDeadEndRouting.classify(error, familyScoped = true))
        assertEquals(OnboardingVariant.ProfileLess, ProfileDeadEndRouting.classify(error, familyScoped = false))
    }

    @Test
    fun `FAMILY_NOT_FOUND routes family-less only when the load is family-scoped`() {
        val error = ApiError.FamilyNotFound("no family", "r_2")
        assertEquals(OnboardingVariant.FamilyLess, ProfileDeadEndRouting.classify(error, familyScoped = true))
        assertNull(ProfileDeadEndRouting.classify(error, familyScoped = false))
    }

    @Test
    fun `every other catalog code is left for the caller's existing error handling`() {
        val others = listOf(
            ApiError.AuthForbidden("x", "r"),
            ApiError.MemberNotFound("x", "r"),
            ApiError.DeviceNotFound("x", "r"),
            ApiError.GroupNotFound("x", "r"),
            ApiError.InviteInvalid("x", "r"),
            ApiError.InviteExpired("x", "r"),
            ApiError.ValidationFailed(null, null, "x", "r"),
            ApiError.InternalError("x", "r"),
            ApiError.RateLimited(null, "x", "r"),
            ApiError.NetworkFailure(RuntimeException("offline")),
        )
        others.forEach { error ->
            assertNull("$error must not route (familyScoped=true)", ProfileDeadEndRouting.classify(error, familyScoped = true))
            assertNull("$error must not route (familyScoped=false)", ProfileDeadEndRouting.classify(error, familyScoped = false))
        }
    }
}
