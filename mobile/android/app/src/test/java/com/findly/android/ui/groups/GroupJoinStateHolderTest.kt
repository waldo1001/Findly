package com.findly.android.ui.groups

import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.fakes.sampleGroupDto
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GroupJoinStateHolder] is pure Kotlin — every code, whether typed by hand or prefilled from the
 * `findly://group-join` deep link, funnels through [GroupJoinCodeSanitizer] before any network call
 * (specs/003-android-client.md §12.2 — "validated by the same pure normalization logic"). */
class GroupJoinStateHolderTest {

    @Test
    fun `an invalid code fails client-side validation without a network call`() = runTest {
        val api = FakeGroupsApi()
        val holder = GroupJoinStateHolder(api, needsDisplayName = false)

        holder.join(code = "not-a-code", displayName = null)

        assertEquals("Enter a valid 8-character group code", holder.state.value.validationError)
        assertTrue(api.joinGroupCalls.isEmpty())
    }

    @Test
    fun `needsDisplayName true requires a non-blank displayName`() = runTest {
        val api = FakeGroupsApi()
        val holder = GroupJoinStateHolder(api, needsDisplayName = true)

        holder.join(code = "7F3K9QRZ", displayName = "")

        assertEquals("Enter a display name", holder.state.value.validationError)
        assertTrue(api.joinGroupCalls.isEmpty())
    }

    @Test
    fun `a valid hyphenated lowercase code is sanitized before the network call`() = runTest {
        val api = FakeGroupsApi().apply {
            joinGroupResult = ApiResult.Success(sampleGroupDto(role = "member"), features = groupsFeatures())
        }
        val holder = GroupJoinStateHolder(api, needsDisplayName = false)

        holder.join(code = "7f3k-9qrz", displayName = "Noor")

        assertNull(holder.state.value.validationError)
        assertEquals("7F3K9QRZ" to "Noor", api.joinGroupCalls.single())
        assertEquals("member", holder.state.value.joined?.role)
        assertEquals(false, holder.state.value.isJoining)
    }

    @Test
    fun `each group-era error code surfaces its own user-facing message`() = runTest {
        val api = FakeGroupsApi()
        val holder = GroupJoinStateHolder(api, needsDisplayName = false)

        api.joinGroupResult = ApiResult.Failure(ApiError.GroupCodeInvalid("raw debug text", "r_1"))
        holder.join("7F3K9QRZ", "Noor")
        assertEquals("That group code isn't valid.", holder.state.value.joinError)

        api.joinGroupResult = ApiResult.Failure(ApiError.GroupAlreadyMember("raw debug text", "r_2"))
        holder.join("7F3K9QRZ", "Noor")
        assertEquals("You're already part of that group.", holder.state.value.joinError)

        api.joinGroupResult = ApiResult.Failure(ApiError.GroupFull(50, "raw debug text", "r_3"))
        holder.join("7F3K9QRZ", "Noor")
        assertEquals("That group is full.", holder.state.value.joinError)

        api.joinGroupResult = ApiResult.Failure(ApiError.GroupExpired("raw debug text", "r_4"))
        holder.join("7F3K9QRZ", "Noor")
        assertEquals("This group has ended.", holder.state.value.joinError)
    }
}
