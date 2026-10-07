package com.findly.android.network

import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.UpdateDeviceRequestDto
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** A61 (specs/011 §1, §2, §4.4; specs/001 §4.1–§4.4, §5.2): the device-lifecycle wire surface
 * against the real Retrofit/OkHttp/kotlinx.serialization stack via [MockWebServer]. */
class DevicesClientTest {

    private lateinit var server: MockWebServer
    private lateinit var client: FindlyApiClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        val auth = FakeAuthProvider()
        client = FindlyApiClient(RetrofitFactory.create(server.url("/").toString(), auth), auth)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `deleteDevice DELETEs v1_devices_id and treats the bare 204 as success`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteDevice("dev-123")

        assertTrue(result is ApiResult.Success)
        val request = server.takeRequest()
        assertEquals("DELETE", request.method)
        assertEquals("/v1/devices/dev-123", request.path)
    }

    @Test
    fun `deleteDevice maps 404 DEVICE_NOT_FOUND and 403 AUTH_FORBIDDEN to their ApiError subtypes`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(404)
                .setBody("""{"error":{"code":"DEVICE_NOT_FOUND","message":"x","requestId":"r1"}}"""),
        )
        server.enqueue(
            MockResponse().setResponseCode(403)
                .setBody("""{"error":{"code":"AUTH_FORBIDDEN","message":"x","requestId":"r2"}}"""),
        )

        val notFound = client.deleteDevice("a") as ApiResult.Failure
        val forbidden = client.deleteDevice("b") as ApiResult.Failure

        assertTrue(notFound.error is ApiError.DeviceNotFound)
        assertTrue(forbidden.error is ApiError.AuthForbidden)
    }

    @Test
    fun `list devices parses staleNudgeEnabled and defaults it to true when absent`() {
        val withField = FindlyJson.decodeFromString<FamilyDeviceDto>(familyDeviceJson(extra = ""","staleNudgeEnabled":false"""))
        val without = FindlyJson.decodeFromString<FamilyDeviceDto>(familyDeviceJson(extra = ""))

        assertFalse(withField.staleNudgeEnabled)
        assertTrue(without.staleNudgeEnabled)
    }

    @Test
    fun `latest locations device parses isDormant and defaults it to false when absent`() {
        val dormant = FindlyJson.decodeFromString<LatestDeviceDto>(latestDeviceJson(extra = ""","isDormant":true"""))
        val absent = FindlyJson.decodeFromString<LatestDeviceDto>(latestDeviceJson(extra = ""))

        assertTrue(dormant.isDormant)
        assertFalse(absent.isDormant)
    }

    @Test
    fun `updateDevice with only staleNudgeEnabled sends exactly that one field`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"data":{"deviceId":"d1","ownerUserId":"u1","platform":"android","deviceName":"P",
                   "model":"P","appVersion":"1","syncIntervalMinutes":15,"trackingEnabled":true,
                   "pushInvalid":false,"staleNudgeEnabled":false},"features":{"subscriptionStatus":"free",
                   "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                             "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
                   "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}}""",
            ),
        )

        val result = client.updateDevice("d1", UpdateDeviceRequestDto(staleNudgeEnabled = false))

        assertTrue(result is ApiResult.Success)
        assertFalse((result as ApiResult.Success).data.staleNudgeEnabled)
        assertEquals("""{"staleNudgeEnabled":false}""", server.takeRequest().body.readUtf8())
    }

    private fun familyDeviceJson(extra: String) =
        """{"deviceId":"d1","ownerUserId":"u1","platform":"ios","deviceName":"P","model":"P",
           "appVersion":"1","syncIntervalMinutes":15,"trackingEnabled":true,"pushInvalid":false,
           "ownerDisplayName":"Noor"$extra}"""

    private fun latestDeviceJson(extra: String) =
        """{"deviceId":"d1","deviceName":"P","trackingEnabled":true,"syncIntervalMinutes":15$extra}"""
}
