package com.findly.android.network

import com.findly.android.fakes.FakeAuthProvider
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * 001-api-contract.md §2.1 / §6.4: a call receiving `AUTH_TOKEN_EXPIRED` forces a token refresh
 * and retries exactly once.
 */
class FindlyApiClientAuthRetryTest {

    private lateinit var server: MockWebServer
    private lateinit var authProvider: FakeAuthProvider
    private lateinit var client: FindlyApiClient

    private val successBody = """
        {"data":{"familyId":"fam_abc","familyName":"Wauters","createdAt":"2026-07-19T08:00:00Z",
                  "me":{"userId":"u1","role":"parent"},"members":[]},
         "features":{"subscriptionStatus":"free",
           "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                     "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
           "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}}
    """.trimIndent()

    private val expiredBody = """{"error":{"code":"AUTH_TOKEN_EXPIRED","message":"expired","requestId":"r_1"}}"""

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        authProvider = FakeAuthProvider(initialToken = "stale-token")
        val service = RetrofitFactory.create(server.url("/").toString(), authProvider)
        client = FindlyApiClient(service, authProvider)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `AUTH_TOKEN_EXPIRED triggers exactly one forced refresh and one retry, then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(200).setBody(successBody))

        val result = client.getMyFamily()

        assertTrue(result is ApiResult.Success)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)

        val firstRequest = server.takeRequest()
        val secondRequest = server.takeRequest()
        assertEquals("Bearer stale-token", firstRequest.getHeader("Authorization"))
        assertEquals("Bearer fresh-token", secondRequest.getHeader("Authorization"))
    }

    @Test
    fun `a second AUTH_TOKEN_EXPIRED surfaces as Failure without a third attempt`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))

        val result = client.getMyFamily()

        assertTrue(result is ApiResult.Failure)
        assertTrue((result as ApiResult.Failure).error is ApiError.AuthTokenExpired)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    // ------------------------------------------------------------------
    // The DRY'd `withAuthRetry` helper (network/FindlyApiClient.kt) must also cover the three
    // body-shape-exception endpoints — bare 204 (removeMember), bare 304 (getGeofences), and the
    // ETag-header-carrying success (replaceGeofences) — not just the generic envelope path above.
    // ------------------------------------------------------------------

    @Test
    fun `removeMember's bare 204 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.removeMember("u2")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertEquals(null, result.features)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `getGeofences's bare 304 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(304))

        val result = client.getGeofences(ifNoneMatch = "\"0x1\"")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(null, result.data)
        assertEquals(null, result.features)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `replaceGeofences's ETag-carrying success retries once on AUTH_TOKEN_EXPIRED`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(
            MockResponse().setResponseCode(200)
                .setHeader("ETag", "\"0x5\"")
                .setBody(
                    """{"data":{"version":5,"geofences":[]},
                        "features":{"subscriptionStatus":"free",
                          "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                                    "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
                          "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}}
                    """.trimIndent(),
                ),
        )

        val result = client.replaceGeofences(ifMatch = "\"0x4\"", geofences = emptyList())

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("\"0x5\"", result.data.etag)
        assertEquals(5, result.data.value.version)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `a second AUTH_TOKEN_EXPIRED on removeMember surfaces as Failure without a third attempt`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))

        val result = client.removeMember("u2")

        assertTrue(result is ApiResult.Failure)
        assertTrue((result as ApiResult.Failure).error is ApiError.AuthTokenExpired)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    // ------------------------------------------------------------------
    // specs/005 (temporary groups) added three more bare-204 endpoints — deleteGroup (§12.5),
    // leaveGroup (§12.8), removeGroupMember (§12.9) — all now funneling through the same
    // `unwrapBare204` helper as removeMember (network/FindlyApiClient.kt). These tests prove the
    // shared helper's retry-once behavior still holds for every one of its four call sites.
    // ------------------------------------------------------------------

    @Test
    fun `deleteGroup's bare 204 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteGroup("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertEquals(null, result.features)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `leaveGroup's bare 204 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.leaveGroup("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertEquals(null, result.features)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `removeGroupMember's bare 204 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.removeGroupMember("grp_1", "u9")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertEquals(null, result.features)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }
}
