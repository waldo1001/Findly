package com.findly.android.ui.devices

import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.defaultFeatures
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.ListDevicesResponseDto
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [DevicesStateHolder] is pure Kotlin (specs/003-android-client.md §14). Unlike the retired
 * `SettingsStateHolder`, it loads `GET /devices` directly with no family probe first — `isParent`
 * is constructor-injected from the caller's cached launch-probe header, mirroring iOS's
 * `DeviceSettingsViewModel(apiClient:isParent:)` (`GET /devices` works without a family, 001
 * §1.5.4/§4). Per-card mutation isolation and per-card error placement (specs/010-app-shell-and-
 * screen-ux.md §4.2) are the load-bearing behaviors this suite pins. */
class DevicesStateHolderTest {

    private fun familyDevice(id: String = "d1", name: String = "Pixel 8", tracking: Boolean = true, interval: Int = 15) =
        FamilyDeviceDto(
            deviceId = id,
            ownerUserId = "uid-parent",
            platform = "android",
            deviceName = name,
            model = "Pixel 8",
            appVersion = "1.0.0",
            syncIntervalMinutes = interval,
            trackingEnabled = tracking,
            pushInvalid = false,
            ownerDisplayName = "Eric",
        )

    @Test
    fun `load populates devices and threads features limits into Content`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(listOf(familyDevice())),
                defaultFeatures(minSyncIntervalMinutes = 15),
            )
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is DevicesUiState.Content)
        state as DevicesUiState.Content
        assertEquals("d1", state.devices.single().deviceId)
        assertEquals("Pixel 8", state.devices.single().renameDraft)
        assertEquals(15, state.limits?.minSyncIntervalMinutes)
    }

    @Test
    fun `a confirmed PROFILE_NOT_FOUND routes to Onboarding profile-less`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.ProfileNotFound("no profile", "r_1"))
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        val state = holder.state.value
        assertTrue(state is DevicesUiState.RouteToOnboarding)
        assertEquals(OnboardingVariant.ProfileLess, (state as DevicesUiState.RouteToOnboarding).variant)
    }

    @Test
    fun `an unrelated load failure surfaces a retryable Error, never a routing outcome`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.InternalError("boom", "r_2"))
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        assertTrue(holder.state.value is DevicesUiState.Error)
    }

    @Test
    fun `a parent toggling tracking commits immediately and updates only that card`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(listOf(familyDevice("d1", tracking = true), familyDevice("d2", tracking = true))),
                defaultFeatures(),
            )
            updateDeviceResult = ApiResult.Success(
                DeviceDto("d1", "uid-parent", "android", "Pixel 8", "Pixel 8", "1.0.0", 15, false, false),
                defaultFeatures(),
            )
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        holder.setTracking("d1", false)

        val state = holder.state.value as DevicesUiState.Content
        val d1 = state.devices.single { it.deviceId == "d1" }
        val d2 = state.devices.single { it.deviceId == "d2" }
        assertEquals(false, d1.trackingEnabled)
        assertEquals(false, d1.isMutating)
        assertNull(d1.error)
        assertEquals(true, d2.trackingEnabled) // untouched sibling card
        assertEquals(listOf("d1" to com.findly.android.network.dto.UpdateDeviceRequestDto(trackingEnabled = false)), devicesApi.updateDeviceCalls)
    }

    @Test
    fun `sync interval selection commits one PATCH with the chosen value`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice())), defaultFeatures())
            updateDeviceResult = ApiResult.Success(
                DeviceDto("d1", "uid-parent", "android", "Pixel 8", "Pixel 8", "1.0.0", 30, true, false),
                defaultFeatures(),
            )
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        holder.setSyncInterval("d1", 30)

        val state = holder.state.value as DevicesUiState.Content
        assertEquals(30, state.devices.single().syncIntervalMinutes)
        assertEquals(1, devicesApi.updateDeviceCalls.size)
    }

    @Test
    fun `a non-parent mutation is blocked client-side, without any network call, and errors only that card`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(listOf(familyDevice("d1"), familyDevice("d2"))),
                defaultFeatures(),
            )
        }
        val holder = DevicesStateHolder(devicesApi, isParent = false, scope = backgroundScope)
        runCurrent()

        holder.setTracking("d1", false)

        val state = holder.state.value as DevicesUiState.Content
        assertEquals("Only a parent can do this", state.devices.single { it.deviceId == "d1" }.error)
        assertNull(state.devices.single { it.deviceId == "d2" }.error)
        assertEquals(0, devicesApi.updateDeviceCalls.size)
        assertEquals(true, state.devices.single { it.deviceId == "d1" }.trackingEnabled) // unchanged
    }

    @Test
    fun `a mutation failure sets only that card's error, leaving other cards untouched`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(listOf(familyDevice("d1"), familyDevice("d2"))),
                defaultFeatures(),
            )
            updateDeviceResult = ApiResult.Failure(ApiError.InternalError("raw debug text", "r_3"))
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        holder.setTracking("d1", false)

        val state = holder.state.value as DevicesUiState.Content
        val d1 = state.devices.single { it.deviceId == "d1" }
        val d2 = state.devices.single { it.deviceId == "d2" }
        assertEquals(false, d1.isMutating)
        assertEquals("Something went wrong on our end. Please try again.", d1.error)
        assertNull(d2.error)
    }

    @Test
    fun `updateRenameDraft edits only the local draft, with no network call`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice())), defaultFeatures())
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()

        holder.updateRenameDraft("d1", "Noor's tablet")

        val state = holder.state.value as DevicesUiState.Content
        assertEquals("Noor's tablet", state.devices.single().renameDraft)
        assertEquals("Pixel 8", state.devices.single().deviceName) // uncommitted
        assertEquals(0, devicesApi.updateDeviceCalls.size)
    }

    @Test
    fun `rename commits deviceName and syncs the draft to the server's echoed value`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice())), defaultFeatures())
            updateDeviceResult = ApiResult.Success(
                DeviceDto("d1", "uid-parent", "android", "Noor's tablet", "Pixel 8", "1.0.0", 15, true, false),
                defaultFeatures(),
            )
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()
        holder.updateRenameDraft("d1", "Noor's tablet")

        holder.rename("d1", "Noor's tablet")

        val state = holder.state.value as DevicesUiState.Content
        val card = state.devices.single()
        assertEquals("Noor's tablet", card.deviceName)
        assertEquals("Noor's tablet", card.renameDraft)
        assertEquals(
            listOf("d1" to com.findly.android.network.dto.UpdateDeviceRequestDto(deviceName = "Noor's tablet")),
            devicesApi.updateDeviceCalls,
        )
    }

    @Test
    fun `a tracking toggle never touches an unrelated card's in-progress rename draft`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(listOf(familyDevice("d1"))), defaultFeatures())
            updateDeviceResult = ApiResult.Success(
                DeviceDto("d1", "uid-parent", "android", "Pixel 8", "Pixel 8", "1.0.0", 15, false, false),
                defaultFeatures(),
            )
        }
        val holder = DevicesStateHolder(devicesApi, isParent = true, scope = backgroundScope)
        runCurrent()
        holder.updateRenameDraft("d1", "mid-typed name")

        holder.setTracking("d1", false)

        val card = (holder.state.value as DevicesUiState.Content).devices.single()
        assertEquals("mid-typed name", card.renameDraft) // preserved, not clobbered by the response's deviceName
        assertEquals(false, card.trackingEnabled)
    }
}
