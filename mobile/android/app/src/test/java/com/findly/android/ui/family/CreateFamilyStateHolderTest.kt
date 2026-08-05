package com.findly.android.ui.family

import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.CreateFamilyResponseDto
import com.findly.android.network.dto.MemberDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [CreateFamilyStateHolder] is pure Kotlin (specs/003-android-client.md §14) — tested with
 * [FakeFamilyApi], mirroring [com.findly.android.ui.groups.CreateGroupStateHolderTest]'s shape.
 * A21: this is the client's only entry point for `POST /families` (001 §3.1) — the endpoint
 * previously existed only in the networking layer with no screen/ViewModel calling it.
 */
class CreateFamilyStateHolderTest {

    @Test
    fun `validate rejects a blank or too-long family name`() {
        val holder = CreateFamilyStateHolder(FakeFamilyApi())
        assertEquals("Family name must be 1-50 characters", holder.validate("", "Eric"))
        assertEquals("Family name must be 1-50 characters", holder.validate("x".repeat(51), "Eric"))
        assertNull(holder.validate("Wauters", "Eric"))
    }

    @Test
    fun `validate rejects a blank or too-long display name`() {
        val holder = CreateFamilyStateHolder(FakeFamilyApi())
        assertEquals("Enter a display name", holder.validate("Wauters", ""))
        assertEquals("Enter a display name", holder.validate("Wauters", "x".repeat(31)))
        assertNull(holder.validate("Wauters", "Eric"))
    }

    @Test
    fun `createFamily success populates created and clears the loading flag`() = runTest {
        val api = FakeFamilyApi().apply {
            createFamilyResult = ApiResult.Success(
                CreateFamilyResponseDto(
                    familyId = "fam_9J2Kq7Lm3NpR5sTvWxYz",
                    familyName = "Wauters",
                    member = MemberDto("uid-1", "parent", "Eric"),
                ),
                features = defaultFeatures(),
            )
        }
        val holder = CreateFamilyStateHolder(api)

        holder.createFamily("Wauters", "Eric")

        val state = holder.state.value
        assertEquals("Wauters", state.created?.familyName)
        assertEquals("parent", state.created?.role)
        assertFalse(state.isCreating)
        assertNull(state.submitError)
        assertEquals(listOf("Wauters" to "Eric"), api.createFamilyCalls)
    }

    @Test
    fun `createFamily validation failure never reaches the network`() = runTest {
        val api = FakeFamilyApi()
        val holder = CreateFamilyStateHolder(api)

        holder.createFamily("", "Eric")

        assertEquals("Family name must be 1-50 characters", holder.state.value.validationError)
        assertTrue(api.createFamilyCalls.isEmpty())
    }

    @Test
    fun `createFamily surfaces FAMILY_ALREADY_MEMBER as the user-facing message, never raw server text`() = runTest {
        val api = FakeFamilyApi().apply {
            createFamilyResult = ApiResult.Failure(ApiError.FamilyAlreadyMember("raw debug text from server", "r_1"))
        }
        val holder = CreateFamilyStateHolder(api)

        holder.createFamily("Wauters", "Eric")

        assertEquals("You're already part of a family.", holder.state.value.submitError)
        assertFalse(holder.state.value.isCreating)
        assertNull(holder.state.value.created)
    }
}
