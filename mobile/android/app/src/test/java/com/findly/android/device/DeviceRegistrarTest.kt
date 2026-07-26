package com.findly.android.device

import com.findly.android.fakes.FakeDeviceInfoProvider
import com.findly.android.fakes.FakeDevicesApi
import com.findly.android.fakes.InMemoryDeviceIdStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DeviceRegistrarTest {

    @Test
    fun `registerOrUpdate omits absent token fields entirely`() = runTest {
        val fakeApi = FakeDevicesApi()
        val registrar = DeviceRegistrar(
            devicesApi = fakeApi,
            deviceIdProvider = DeviceIdProvider(InMemoryDeviceIdStore(), idGenerator = { "fixed-device-id" }),
            deviceInfoProvider = FakeDeviceInfoProvider(),
        )

        registrar.registerOrUpdate(uid = "uid-1")

        val request = fakeApi.registerDeviceCalls.single()
        assertEquals("fixed-device-id", request.deviceId)
        assertEquals("android", request.platform)
        assertEquals("Pixel 8", request.model)
        assertEquals("1.0.0", request.appVersion)
        assertNull(request.pushToken)
        assertNull(request.locationPushToken)
    }

    @Test
    fun `deviceId is stable per uid across calls`() = runTest {
        val fakeApi = FakeDevicesApi()
        val registrar = DeviceRegistrar(
            devicesApi = fakeApi,
            deviceIdProvider = DeviceIdProvider(InMemoryDeviceIdStore()),
            deviceInfoProvider = FakeDeviceInfoProvider(),
        )

        registrar.registerOrUpdate(uid = "uid-1")
        registrar.registerOrUpdate(uid = "uid-1")

        val (first, second) = fakeApi.registerDeviceCalls
        assertEquals(first.deviceId, second.deviceId)
    }

    @Test
    fun `onPushTokenRefreshed triggers exactly one registerOrUpdate call carrying the new token`() = runTest {
        val fakeApi = FakeDevicesApi()
        val registrar = DeviceRegistrar(
            devicesApi = fakeApi,
            deviceIdProvider = DeviceIdProvider(InMemoryDeviceIdStore()),
            deviceInfoProvider = FakeDeviceInfoProvider(),
        )

        registrar.onPushTokenRefreshed(uid = "uid-1", newToken = "new-fcm-token")

        assertEquals(1, fakeApi.registerDeviceCalls.size)
        assertEquals("new-fcm-token", fakeApi.registerDeviceCalls.single().pushToken)
    }

    /** A9 (specs/009-device-runtime.md §5.1): push handlers (e.g. `LocateRequestPushHandler`) need
     * the current device's `deviceId` without going through a full `registerOrUpdate` call. */
    @Test
    fun `deviceIdFor returns the same stable id registerOrUpdate would have used`() = runTest {
        val fakeApi = FakeDevicesApi()
        val registrar = DeviceRegistrar(
            devicesApi = fakeApi,
            deviceIdProvider = DeviceIdProvider(InMemoryDeviceIdStore(), idGenerator = { "fixed-device-id" }),
            deviceInfoProvider = FakeDeviceInfoProvider(),
        )

        val direct = registrar.deviceIdFor("uid-1")
        registrar.registerOrUpdate(uid = "uid-1")

        assertEquals("fixed-device-id", direct)
        assertEquals(direct, fakeApi.registerDeviceCalls.single().deviceId)
    }
}
