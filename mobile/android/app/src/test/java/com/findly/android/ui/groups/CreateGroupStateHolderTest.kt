package com.findly.android.ui.groups

import com.findly.android.fakes.FakeGroupsApi
import com.findly.android.fakes.groupsFeatures
import com.findly.android.fakes.sampleGroupDto
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.PlanLimits
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [CreateGroupStateHolder] is pure Kotlin — a fixed [clock] makes the `now + 1h` / `now +
 * maxGroupDurationDays` bounds (001-api-contract.md §12.1) deterministic under test. */
class CreateGroupStateHolderTest {

    private val fixedNowMillis = 1_784_707_200_000L // 2026-07-21T10:00:00Z (test fixture epoch)
    private val limits = groupsFeatures().limits // maxActiveGroups=5, maxGroupDurationDays=30, ...

    private fun holder(api: FakeGroupsApi, limits: PlanLimits? = this.limits, needsDisplayName: Boolean = false) =
        CreateGroupStateHolder(api, limits, needsDisplayName, clock = { fixedNowMillis })

    @Test
    fun `an endsAt less than 1h from now fails client-side validation without a network call`() = runTest {
        val api = FakeGroupsApi()
        val h = holder(api)

        h.createGroup(name = "Festival crew", endsAtMillis = fixedNowMillis + 30 * 60_000, expiryPolicy = "delete", displayName = null)

        assertEquals("End time must be at least 1 hour from now", h.state.value.validationError)
        assertTrue(api.createGroupCalls.isEmpty())
    }

    @Test
    fun `an endsAt beyond maxGroupDurationDays fails client-side validation without a network call`() = runTest {
        val api = FakeGroupsApi()
        val h = holder(api) // maxGroupDurationDays = 30

        val endsAt31DaysOut = fixedNowMillis + 31L * 24 * 60 * 60 * 1000
        h.createGroup(name = "Festival crew", endsAtMillis = endsAt31DaysOut, expiryPolicy = "delete", displayName = null)

        assertEquals("That end date is further out than your plan allows", h.state.value.validationError)
        assertTrue(api.createGroupCalls.isEmpty())
    }

    @Test
    fun `a null limits (defensive) never enforces a max-duration ceiling`() = runTest {
        val api = FakeGroupsApi().apply {
            createGroupResult = ApiResult.Success(sampleGroupDto(), features = groupsFeatures())
        }
        val h = holder(api, limits = null)

        val farOut = fixedNowMillis + 400L * 24 * 60 * 60 * 1000
        h.createGroup(name = "Festival crew", endsAtMillis = farOut, expiryPolicy = "delete", displayName = null)

        assertNull(h.state.value.validationError)
        assertEquals(1, api.createGroupCalls.size)
    }

    @Test
    fun `a blank name fails client-side validation`() = runTest {
        val api = FakeGroupsApi()
        val h = holder(api)

        h.createGroup(name = "  ", endsAtMillis = fixedNowMillis + 2 * 60 * 60 * 1000, expiryPolicy = "delete", displayName = null)

        assertEquals("Name must be 1-50 characters", h.state.value.validationError)
        assertTrue(api.createGroupCalls.isEmpty())
    }

    @Test
    fun `an unrecognized expiryPolicy fails client-side validation`() = runTest {
        val api = FakeGroupsApi()
        val h = holder(api)

        h.createGroup(name = "Festival crew", endsAtMillis = fixedNowMillis + 2 * 60 * 60 * 1000, expiryPolicy = "bogus", displayName = null)

        assertEquals("Choose a group type", h.state.value.validationError)
        assertTrue(api.createGroupCalls.isEmpty())
    }

    @Test
    fun `needsDisplayName true requires a non-blank displayName`() = runTest {
        val api = FakeGroupsApi()
        val h = holder(api, needsDisplayName = true)

        h.createGroup(name = "Festival crew", endsAtMillis = fixedNowMillis + 2 * 60 * 60 * 1000, expiryPolicy = "delete", displayName = " ")

        assertEquals("Enter a display name", h.state.value.validationError)
        assertTrue(api.createGroupCalls.isEmpty())
    }

    @Test
    fun `a valid request calls createGroup with an ISO-8601 UTC endsAt and populates created`() = runTest {
        val api = FakeGroupsApi().apply {
            createGroupResult = ApiResult.Success(sampleGroupDto(), features = groupsFeatures())
        }
        val h = holder(api)
        val endsAtMillis = fixedNowMillis + 2 * 60 * 60 * 1000 // +2h

        h.createGroup(name = "Festival crew", endsAtMillis = endsAtMillis, expiryPolicy = "delete", displayName = null)

        assertNull(h.state.value.validationError)
        assertNull(h.state.value.submitError)
        assertEquals(false, h.state.value.isCreating)
        assertEquals("Festival crew", h.state.value.created?.name)
        val call = api.createGroupCalls.single()
        assertEquals("Festival crew", call.name)
        assertEquals("delete", call.expiryPolicy)
        assertTrue("endsAt must be ISO-8601 UTC (Z-suffixed): ${call.endsAt}", call.endsAt.endsWith("Z"))
    }

    @Test
    fun `a server failure surfaces the user-facing message, never raw server text`() = runTest {
        val api = FakeGroupsApi().apply {
            createGroupResult = ApiResult.Failure(ApiError.LimitExceeded("maxActiveGroups", "raw debug text", "r_1"))
        }
        val h = holder(api)

        h.createGroup(name = "Festival crew", endsAtMillis = fixedNowMillis + 2 * 60 * 60 * 1000, expiryPolicy = "delete", displayName = null)

        assertEquals("You've reached your active-group limit for this plan.", h.state.value.submitError)
        assertEquals(false, h.state.value.isCreating)
        assertNull(h.state.value.created)
    }
}
