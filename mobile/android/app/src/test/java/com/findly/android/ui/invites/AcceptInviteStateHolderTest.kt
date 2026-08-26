package com.findly.android.ui.invites

import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.AcceptInviteResponseDto
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.ListDevicesResponseDto
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
    // displayName when one exists". 001 §4.2's own text settles the wire shape: "A family-less
    // caller gets their own devices only (same response shape; ownerDisplayName = their profile
    // displayName)" -- GET /devices needs no family and no new endpoint, so for the "Manage
    // family invites" entry point (an already-profiled, family-less caller) any returned
    // device's ownerDisplayName IS the caller's own profile displayName.

    @Test
    fun `loadDisplayNameFallback resolves the caller's own name from the first device's ownerDisplayName`() = runTest {
        val familyApi = FakeFamilyApi()
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
    }

    @Test
    fun `loadDisplayNameFallback leaves null when the caller has no devices yet`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(devices = emptyList()), defaultFeatures())
        }
        val holder = AcceptInviteStateHolder(FakeFamilyApi(), devicesApi)

        holder.loadDisplayNameFallback()

        assertNull(holder.state.value.displayNameFallback)
    }

    @Test
    fun `loadDisplayNameFallback leaves null on a listDevices failure -- never blocks the screen`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_20"))
        }
        val holder = AcceptInviteStateHolder(FakeFamilyApi(), devicesApi)

        holder.loadDisplayNameFallback()

        assertNull(holder.state.value.displayNameFallback)
    }
}
