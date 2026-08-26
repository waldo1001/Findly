package com.findly.android.ui.settings

import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeFamilyApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.CallerRoleDto
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.ListDevicesResponseDto
import com.findly.android.network.dto.MemberDto
import com.findly.android.network.dto.UpdateMemberRequestDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** [SettingsStateHolder] is pure Kotlin — tested with [FakeFamilyApi]/[FakeDevicesApi]
 * (specs/003-android-client.md §14, §16): parent-vs-owner permission gating (001-api-contract.md
 * §3.5/§3.6/§4.3) is enforced client-side before any network call. */
class SettingsStateHolderTest {

    private fun familyDevice(id: String = "d1", tracking: Boolean = true) = FamilyDeviceDto(
        deviceId = id,
        ownerUserId = "uid-parent",
        platform = "android",
        deviceName = "Pixel 8",
        model = "Pixel 8",
        appVersion = "1.0.0",
        syncIntervalMinutes = 15,
        trackingEnabled = tracking,
        pushInvalid = false,
        ownerDisplayName = "Eric",
    )

    @Test
    fun `load populates myRole, members, and devices`() = runTest {
        val familyApi = FakeFamilyApi()
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice())), defaultFeatures())
        }
        val holder = SettingsStateHolder(familyApi, devicesApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is SettingsUiState.Content)
        state as SettingsUiState.Content
        assertEquals("parent", state.myRole)
        assertEquals(2, state.members.size)
        assertEquals("d1", state.devices.single().deviceId)
    }

    @Test
    fun `getMyFamily failure (unrelated to profile family) surfaces Error without calling listDevices`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.InternalError("boom", "r_1"))
        }
        val devicesApi = FakeDevicesApi()
        val holder = SettingsStateHolder(familyApi, devicesApi, backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is SettingsUiState.Error)
        assertEquals(0, devicesApi.listDevicesCallCount)
    }

    @Test
    fun `listDevices failure surfaces Error`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.InternalError("boom", null))
        }
        val holder = SettingsStateHolder(FakeFamilyApi(), devicesApi, backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is SettingsUiState.Error)
    }

    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule — GET /families/me and GET /devices
    // are both family-scoped (001 §1.6) for this screen's purposes.

    @Test
    fun `PROFILE_NOT_FOUND on the family load routes to Onboarding profile-less, never calling listDevices`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_2"))
        }
        val devicesApi = FakeDevicesApi()
        val holder = SettingsStateHolder(familyApi, devicesApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is SettingsUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as SettingsUiState.RouteToOnboarding).variant)
        assertEquals(0, devicesApi.listDevicesCallCount)
    }

    @Test
    fun `FAMILY_NOT_FOUND on the family load routes to Onboarding family-less, never calling listDevices`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            getMyFamilyResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_3"))
        }
        val devicesApi = FakeDevicesApi()
        val holder = SettingsStateHolder(familyApi, devicesApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is SettingsUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as SettingsUiState.RouteToOnboarding).variant)
        assertEquals(0, devicesApi.listDevicesCallCount)
    }

    @Test
    fun `FAMILY_NOT_FOUND on the devices load routes to Onboarding family-less`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.FamilyNotFound("no family", "r_4"))
        }
        val holder = SettingsStateHolder(FakeFamilyApi(), devicesApi, backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is SettingsUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.FamilyLess, (state as SettingsUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `a parent updating device settings succeeds and updates the local device`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice())), defaultFeatures())
            updateDeviceResult = ApiResult.Success(
                DeviceDto("d1", "uid-parent", "android", "Pixel 8", "Pixel 8", "1.0.0", 30, false, false),
                defaultFeatures(),
            )
        }
        val holder = SettingsStateHolder(FakeFamilyApi(), devicesApi, backgroundScope)
        runCurrent()

        holder.updateDeviceSettings("d1", trackingEnabled = false)

        val state = holder.state.value as SettingsUiState.Content
        assertEquals(false, state.devices.single().trackingEnabled)
        assertEquals(false, state.isMutating)
        assertEquals(1, devicesApi.updateDeviceCalls.size)
    }

    @Test
    fun `a non-parent updating device settings is blocked client-side without a network call`() = runTest {
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
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice())), defaultFeatures())
        }
        val holder = SettingsStateHolder(familyApi, devicesApi, backgroundScope)
        runCurrent()

        holder.updateDeviceSettings("d1", trackingEnabled = false)

        val state = holder.state.value as SettingsUiState.Content
        assertEquals("Only a parent can do this", state.mutationError)
        assertEquals(0, devicesApi.updateDeviceCalls.size)
        assertEquals(true, state.devices.single().trackingEnabled)
    }

    @Test
    fun `a parent updating a member role succeeds`() = runTest {
        val familyApi = FakeFamilyApi().apply {
            updateMemberResult = ApiResult.Success(
                MemberDto("uid-member", "parent", "Noor", "2026-07-02T00:00:00Z"),
                defaultFeatures(),
            )
        }
        val holder = SettingsStateHolder(familyApi, FakeDevicesApi(), backgroundScope)
        runCurrent()

        holder.updateMember("uid-member", role = "parent")

        val state = holder.state.value as SettingsUiState.Content
        assertEquals("parent", state.members.single { it.userId == "uid-member" }.role)
        assertEquals(listOf("uid-member" to UpdateMemberRequestDto(role = "parent")), familyApi.updateMemberCalls)
    }

    @Test
    fun `removeMember by a parent removes the member from the local roster`() = runTest {
        val holder = SettingsStateHolder(FakeFamilyApi(), FakeDevicesApi(), backgroundScope)
        runCurrent()

        holder.removeMember("uid-member")

        val state = holder.state.value as SettingsUiState.Content
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
        val holder = SettingsStateHolder(familyApi, FakeDevicesApi(), backgroundScope)
        runCurrent()

        holder.removeMember("uid-parent")

        val state = holder.state.value as SettingsUiState.Content
        assertEquals("A family must always have at least one parent.", state.mutationError)
        assertTrue(state.members.any { it.userId == "uid-parent" })
    }
}
