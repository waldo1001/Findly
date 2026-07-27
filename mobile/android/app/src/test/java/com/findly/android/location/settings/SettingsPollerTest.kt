package com.findly.android.location.settings

import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.FakeGeofenceRegistry
import com.findly.android.fakes.FakeSyncScheduler
import com.findly.android.fakes.InMemoryDeviceSettingsStateStore
import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.ListDevicesResponseDto
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Verifies specs/009-device-runtime.md §4's pull-based resume poll: `GET /devices`, find this
 * device's own row, apply through [DeviceSettingsCoordinator]. */
class SettingsPollerTest {

    private fun familyDevice(deviceId: String, syncIntervalMinutes: Int, trackingEnabled: Boolean) = FamilyDeviceDto(
        deviceId = deviceId,
        ownerUserId = "uid-1",
        platform = "android",
        deviceName = "Pixel 8",
        model = "Pixel 8",
        appVersion = "1.0.0",
        syncIntervalMinutes = syncIntervalMinutes,
        trackingEnabled = trackingEnabled,
        pushInvalid = false,
        ownerDisplayName = "Alex",
    )

    @Test
    fun `finds this device's own row and applies its settings`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(
                    devices = listOf(
                        familyDevice("other-device", 5, true),
                        familyDevice("this-device", 60, true),
                    ),
                ),
                features = null,
            )
        }
        val scheduler = FakeSyncScheduler()
        val coordinator = DeviceSettingsCoordinator(scheduler, FakeGeofenceRegistry(), InMemoryDeviceSettingsStateStore())
        val poller = SettingsPoller(devicesApi, deviceId = "this-device", settingsCoordinator = coordinator)

        val outcome = poller.poll()

        assertEquals(PollOutcome.Applied, outcome)
        assertEquals(listOf(60), scheduler.rescheduleCalls)
    }

    @Test
    fun `resume - trackingEnabled flips back to true and the schedule is restored`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(
                ListDevicesResponseDto(devices = listOf(familyDevice("this-device", 15, true))),
                features = null,
            )
        }
        val scheduler = FakeSyncScheduler()
        val stateStore = InMemoryDeviceSettingsStateStore(DeviceSettingsSnapshot(15, false))
        val coordinator = DeviceSettingsCoordinator(scheduler, FakeGeofenceRegistry(), stateStore)
        val poller = SettingsPoller(devicesApi, deviceId = "this-device", settingsCoordinator = coordinator)

        poller.poll()

        assertEquals(listOf(15), scheduler.rescheduleCalls)
        assertEquals(true, stateStore.current()?.trackingEnabled)
    }

    @Test
    fun `own device missing from the roster is reported distinctly`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Success(ListDevicesResponseDto(devices = emptyList()), features = null)
        }
        val coordinator = DeviceSettingsCoordinator(FakeSyncScheduler(), FakeGeofenceRegistry(), InMemoryDeviceSettingsStateStore())
        val poller = SettingsPoller(devicesApi, deviceId = "this-device", settingsCoordinator = coordinator)

        val outcome = poller.poll()

        assertEquals(PollOutcome.DeviceNotFound, outcome)
    }

    @Test
    fun `a network failure is surfaced, not swallowed`() = runTest {
        val devicesApi = FakeDevicesApi().apply {
            listDevicesResult = ApiResult.Failure(ApiError.NetworkFailure(RuntimeException("offline")))
        }
        val coordinator = DeviceSettingsCoordinator(FakeSyncScheduler(), FakeGeofenceRegistry(), InMemoryDeviceSettingsStateStore())
        val poller = SettingsPoller(devicesApi, deviceId = "this-device", settingsCoordinator = coordinator)

        val outcome = poller.poll()

        assertTrue(outcome is PollOutcome.Failed)
    }
}
