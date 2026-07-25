package com.findly.android.network

import com.findly.android.fakes.FakeAuthProvider
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Exercises the real Retrofit/OkHttp/kotlinx.serialization stack against a local
 * [MockWebServer] — a genuine JVM socket server, not a hand-mocked substitute
 * (specs/003-android-client.md §14). Covers envelope success/error unwrapping and the two
 * documented body-less exceptions (§3.6's 204, §7.1's 304).
 */
class EnvelopeParsingTest {

    private lateinit var server: MockWebServer
    private lateinit var authProvider: FakeAuthProvider
    private lateinit var client: FindlyApiClient

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        authProvider = FakeAuthProvider()
        val service = RetrofitFactory.create(server.url("/").toString(), authProvider)
        client = FindlyApiClient(service, authProvider)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `success envelope unwraps data and features`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(201).setBody(
                """
                {"data":{"familyId":"fam_abc","familyName":"Wauters",
                          "member":{"userId":"u1","role":"parent","displayName":"Eric"}},
                 "features":{"subscriptionStatus":"free",
                   "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                             "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
                   "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}}
                """.trimIndent(),
            ),
        )

        val result = client.createFamily("Wauters", "Eric")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("fam_abc", result.data.familyId)
        assertEquals("parent", result.data.member.role)
        assertEquals(10, result.features?.limits?.maxDevices)
        assertEquals("free", result.features?.subscriptionStatus)
    }

    @Test
    fun `error envelope unwraps into the matching ApiError subtype with requestId`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(404).setBody(
                """{"error":{"code":"FAMILY_NOT_FOUND","message":"no family","requestId":"r_xyz789"}}""",
            ),
        )

        val result = client.getMyFamily()

        assertTrue(result is ApiResult.Failure)
        val error = (result as ApiResult.Failure).error
        assertTrue(error is ApiError.FamilyNotFound)
        assertEquals("r_xyz789", error.requestId)
    }

    @Test
    fun `removeMember 204 yields Success(Unit, features = null)`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.removeMember("u2")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertNull(result.features)
    }

    @Test
    fun `getGeofences 304 yields Success(null, features = null) and sends If-None-Match`() = runTest {
        server.enqueue(MockResponse().setResponseCode(304))

        val result = client.getGeofences(ifNoneMatch = "\"0x1\"")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertNull(result.data)
        assertNull(result.features)

        val recorded = server.takeRequest()
        assertEquals("\"0x1\"", recorded.getHeader("If-None-Match"))
    }

    @Test
    fun `getGeofences 200 carries the ETag response header`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200)
                .setHeader("ETag", "\"0x2\"")
                .setBody(
                    """
                    {"data":{"version":4,"geofences":[]},
                     "features":{"subscriptionStatus":"free",
                       "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                                 "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
                       "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}}
                    """.trimIndent(),
                ),
        )

        val result = client.getGeofences()

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("\"0x2\"", result.data?.etag)
        assertEquals(4, result.data?.value?.version)
    }

    @Test
    fun `latest-locations response tolerates a never-reported device (all-null fields)`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"members":[{"userId":"u2","displayName":"Noor","devices":[
                    {"deviceId":"d1","deviceName":"Noor's phone","lat":null,"lon":null,
                     "recordedAt":null,"trackingEnabled":true,"syncIntervalMinutes":15,"isStale":null}
                ]}]},
                 "features":{"subscriptionStatus":"free",
                   "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                             "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
                   "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}}
                """.trimIndent(),
            ),
        )

        val result = client.getLatestLocations()

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        val device = result.data.members.single().devices.single()
        assertNull(device.lat)
        assertNull(device.isStale)
        assertEquals(true, device.trackingEnabled)
    }
}
