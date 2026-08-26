package com.findly.android.ui.invites

import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.AcceptInviteResponseDto
import com.findly.android.network.dto.CallerRoleDto
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.ListDevicesResponseDto
import com.findly.android.network.dto.MemberDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [AcceptInviteStateHolder] is pure Kotlin — tested with [FakeFamilyApi] (specs/003-android-
 * client.md §14, §16). Split out of the retired `InvitesStateHolder` (specs/010-app-shell-and-
 * screen-ux.md §5.2/§6: "Android's combined Invites screen splits into create + accept").
 * `acceptInvite` runs the raw [inviteCode] through [FamilyInviteCodeSanitizer] before it ever
 * reaches the network (010 §5.2: "normalization before the network call is unchanged") — every
 * test below passes an already-canonical code except the ones that specifically exercise
 * normalization.
 */
class AcceptInviteStateHolderTest {

    @Test
    fun `acceptInvite success populates acceptedFamily`() = runTest {
        val api = FakeFamilyApi().apply {
            acceptInviteResult = ApiResult.Success(
                AcceptInviteResponseDto("fam_test", "Wauters", "member"),
                defaultFeatures(),
            )
        }
        val holder = AcceptInviteStateHolder(api, FakeDevicesApi())

        holder.acceptInvite(inviteCode = "7F3K9QRZ", displayName = "Noor")

        val state = holder.state.value
        assertEquals("Wauters", state.acceptedFamily?.familyName)
        assertEquals(false, state.isAcceptingInvite)
        assertNull(state.acceptInviteError)
        assertEquals(listOf("7F3K9QRZ" to "Noor"), api.acceptInviteCalls)
    }

    @Test
    fun `a hyphenated display-form code is normalized before the network call`() = runTest {
        val api = FakeFamilyApi().apply {
            acceptInviteResult = ApiResult.Success(AcceptInviteResponseDto("fam_test", "Wauters", "member"), defaultFeatures())
        }
        val holder = AcceptInviteStateHolder(api, FakeDevicesApi())

        holder.acceptInvite(inviteCode = "7f3k-9qrz", displayName = "Noor")

        assertEquals(listOf("7F3K9QRZ" to "Noor"), api.acceptInviteCalls)
    }

    @Test
    fun `an invalid code never reaches the network`() = runTest {
        val api = FakeFamilyApi()
        val holder = AcceptInviteStateHolder(api, FakeDevicesApi())

        holder.acceptInvite(inviteCode = "not-a-code", displayName = "Noor")

        val state = holder.state.value
        assertEquals("Enter a valid 8-character invite code", state.acceptInviteError)
        assertTrue(api.acceptInviteCalls.isEmpty())
        assertNull(state.acceptedFamily)
    }

    @Test
    fun `acceptInvite with a blank display name surfaces a validation message and never reaches the network`() = runTest {
        val api = FakeFamilyApi()
        val holder = AcceptInviteStateHolder(api, FakeDevicesApi())

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
        val holder = AcceptInviteStateHolder(api, FakeDevicesApi())

        // Valid, Crockford-base32 (no I/L/O/U) codes -- AcceptInviteStateHolder now sanitizes
        // before the network call (unlike the retired combined InvitesStateHolder), so a test
        // code containing an excluded letter would be rejected client-side before ever reaching
        // these fakes' scripted server errors.
        api.acceptInviteResult = ApiResult.Failure(ApiError.InviteInvalid("raw debug text from server", "r_1"))
        holder.acceptInvite("AAAA1111", "Noor")
        assertEquals("That invite code isn't valid.", holder.state.value.acceptInviteError)

        api.acceptInviteResult = ApiResult.Failure(ApiError.InviteAlreadyUsed("raw debug text from server", "r_2"))
        holder.acceptInvite("BBBB2222", "Noor")
        assertEquals("That invite code has already been used.", holder.state.value.acceptInviteError)

        api.acceptInviteResult = ApiResult.Failure(ApiError.InviteExpired("raw debug text from server", "r_3"))
        holder.acceptInvite("CCCC3333", "Noor")
        assertEquals("This invite code has expired.", holder.state.value.acceptInviteError)

        api.acceptInviteResult = ApiResult.Failure(ApiError.FamilyAlreadyMember("raw debug text from server", "r_4"))
        holder.acceptInvite("DDDD4444", "Noor")
        assertEquals("You're already part of a family.", holder.state.value.acceptInviteError)
    }

    // specs/010-app-shell-and-screen-ux.md §5.2: "prefilled with the caller's existing profile
    // displayName when one exists". 001 §4.2's FULL sentence is the wire-shape guarantee this
    // gates on: "Open family: all members see all devices... A family-less caller gets their
    // own devices only (same response shape; ownerDisplayName = their profile displayName)." The
    // ownerDisplayName == caller's-own-name guarantee holds ONLY for a family-less caller -- for
    // a caller who already has a family, GET /devices returns every member's devices in an
    // unspecified order, so firstOrNull()?.ownerDisplayName could be a completely different
    // family member (round-2 review finding: reachable via a deep link into this screen with no
    // Onboarding-typed name and no check of the caller's current family state -- a PII
    // misattribution risk, not a cosmetic one). loadDisplayNameFallback() therefore probes
    // GET /families/me FIRST: a family caller's own name comes from that response's own
    // `members` list (matched by `me.userId`) and GET /devices is never called; only a confirmed
    // FAMILY_NOT_FOUND unlocks the GET /devices fallback, where §4.2's guarantee genuinely holds.

    @Test
    fun `loadDisplayNameFallback resolves the caller's own name from GET families me when the caller has a family, and never calls listDevices`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Success(
                FamilyMeResponseDto(
                    familyId = "fam_test",
                    familyName = "Wauters",
                    createdAt = "2026-07-01T00:00:00Z",
                    me = CallerRoleDto("uid-caller", "member"),
                    members = listOf(
                        MemberDto("uid-other", "parent", "Someone Else", "2026-07-01T00:00:00Z"),
                        MemberDto("uid-caller", "member", "Noor", "2026-07-02T00:00:00Z"),
                    ),
                ),
                defaultFeatures(),
            )
        }
        val devicesApi = FakeDevicesApi().apply {
            // Scripted with a DIFFERENT member's name -- if the gate is wrong and this ever gets
            // called, the assertion below on displayNameFallback would catch the misattribution
            // even before the explicit listDevicesCallCount check does.
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(
                    devices = listOf(
                        FamilyDeviceDto(
                            deviceId = "device-1",
                            ownerUserId = "uid-other",
                            platform = "android",
                            deviceName = "Pixel 8",
                            model = "Pixel 8",
                            appVersion = "1.0.0",
                            syncIntervalMinutes = 15,
                            trackingEnabled = true,
                            pushInvalid = false,
                            ownerDisplayName = "Someone Else",
                        ),
                    ),
                ),
                defaultFeatures(),
            )
        }
        val holder = AcceptInviteStateHolder(familyApi, devicesApi)

        holder.loadDisplayNameFallback()

        assertEquals("Noor", holder.state.value.displayNameFallback)
        assertEquals(0, devicesApi.listDevicesCallCount)
    }

    @Test
    fun `loadDisplayNameFallback resolves the caller's own name from the first device's ownerDisplayName when genuinely family-less`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_30"))
        }
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(
                    devices = listOf(
                        FamilyDeviceDto(
                            deviceId = "device-1",
                            ownerUserId = "uid-test",
                            platform = "android",
                            deviceName = "Pixel 8",
                            model = "Pixel 8",
                            appVersion = "1.0.0",
                            syncIntervalMinutes = 15,
                            trackingEnabled = true,
                            pushInvalid = false,
                            ownerDisplayName = "Noor",
                        ),
                    ),
                ),
                defaultFeatures(),
            )
        }
        val holder = AcceptInviteStateHolder(familyApi, devicesApi)

        holder.loadDisplayNameFallback()

        assertEquals("Noor", holder.state.value.displayNameFallback)
        assertEquals(1, devicesApi.listDevicesCallCount)
    }

    @Test
    fun `loadDisplayNameFallback leaves null when family-less with no devices yet`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_31"))
        }
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(devices = emptyList()), defaultFeatures())
        }
        val holder = AcceptInviteStateHolder(familyApi, devicesApi)

        holder.loadDisplayNameFallback()

        assertNull(holder.state.value.displayNameFallback)
    }

    @Test
    fun `loadDisplayNameFallback leaves null when family-less and listDevices fails -- never blocks the screen`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_32"))
        }
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_33"))
        }
        val holder = AcceptInviteStateHolder(familyApi, devicesApi)

        holder.loadDisplayNameFallback()

        assertNull(holder.state.value.displayNameFallback)
    }

    @Test
    fun `loadDisplayNameFallback leaves null on an ambiguous families me outcome, and never calls listDevices`() = runTest {
        // Anything other than a confirmed FAMILY_NOT_FOUND (a transient failure, an unexpected
        // catalog code, ...) must NOT be treated as "genuinely family-less" -- the whole point
        // of the round-2 fix is that GET /devices is only safe to trust once family-less is
        // actually confirmed, never assumed from an ambiguous outcome.
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile yet", "r_34"))
        }
        val devicesApi = FakeDevicesApi()
        val holder = AcceptInviteStateHolder(familyApi, devicesApi)

        holder.loadDisplayNameFallback()

        assertNull(holder.state.value.displayNameFallback)
        assertEquals(0, devicesApi.listDevicesCallCount)
    }
}
