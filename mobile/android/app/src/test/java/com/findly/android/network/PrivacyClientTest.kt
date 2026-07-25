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
 * `PrivacyApi` request-building against the real Retrofit/OkHttp/kotlinx.serialization stack via
 * a local [MockWebServer] (001-api-contract.md §13; specs/008-privacy-endpoints.md;
 * specs/003-android-client.md §12.4). Covers the one unenveloped response in the API (§13.1) and
 * the two bare-204 deletions (§13.2/§13.3).
 */
class PrivacyClientTest {

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

    // ------------------------------------------------------------------
    // 13.1 Export — the one unenveloped response in the API
    // ------------------------------------------------------------------

    @Test
    fun `exportData GETs v1_export without a userId and returns the raw unparsed body`() = runTest {
        val exportJson = """{"formatVersion":1,"generatedAt":"2026-07-25T14:00:00Z","subject":{"userId":"u1"}}"""
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json; charset=utf-8")
                .setHeader("Content-Disposition", "attachment; filename=\"findly-export-u1-2026-07-25.json\"")
                .setBody(exportJson),
        )

        val result = client.exportData()

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(exportJson, String(result.data.body))
        assertEquals("findly-export-u1-2026-07-25.json", result.data.suggestedFileName)
        assertEquals("application/json; charset=utf-8", result.data.contentType)
        assertNull("13.1 is unenveloped — there is no features object", result.features)

        val recorded = server.takeRequest()
        assertEquals("GET", recorded.method)
        assertEquals("/v1/export", recorded.path)
    }

    @Test
    fun `exportData with a userId adds it as a query parameter (parent exporting a member)`() = runTest {
        server.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        client.exportData(userId = "uid-member")

        val recorded = server.takeRequest()
        assertEquals("/v1/export?userId=uid-member", recorded.path)
    }

    @Test
    fun `exportData maps a 402 exportsPerDay error like any other endpoint`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(402).setBody(
                """{"error":{"code":"LIMIT_EXCEEDED","message":"quota","details":{"limit":"exportsPerDay"},"requestId":"r_1"}}""",
            ),
        )

        val result = client.exportData()

        assertTrue(result is ApiResult.Failure)
        val error = (result as ApiResult.Failure).error
        assertTrue(error is ApiError.LimitExceeded)
        assertEquals("exportsPerDay", (error as ApiError.LimitExceeded).limit)
    }

    @Test
    fun `exportData's bare success retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(
            MockResponse().setResponseCode(401)
                .setBody("""{"error":{"code":"AUTH_TOKEN_EXPIRED","message":"expired","requestId":"r_1"}}"""),
        )
        server.enqueue(MockResponse().setResponseCode(200).setBody("{\"formatVersion\":1}"))

        val result = client.exportData()

        assertTrue(result is ApiResult.Success)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    // ------------------------------------------------------------------
    // 13.2 Delete my account
    // ------------------------------------------------------------------

    @Test
    fun `deleteAccount DELETEs v1_users_me and unwraps the bare 204`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteAccount()

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertNull(result.features)

        val recorded = server.takeRequest()
        assertEquals("DELETE", recorded.method)
        assertEquals("/v1/users/me", recorded.path)
    }

    @Test
    fun `deleteAccount's bare 204 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(
            MockResponse().setResponseCode(401)
                .setBody("""{"error":{"code":"AUTH_TOKEN_EXPIRED","message":"expired","requestId":"r_1"}}"""),
        )
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteAccount()

        assertTrue(result is ApiResult.Success)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    // ------------------------------------------------------------------
    // 13.3 Delete my family
    // ------------------------------------------------------------------

    @Test
    fun `deleteFamily DELETEs v1_families_me and unwraps the bare 204`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteFamily()

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertNull(result.features)

        val recorded = server.takeRequest()
        assertEquals("DELETE", recorded.method)
        assertEquals("/v1/families/me", recorded.path)
    }

    @Test
    fun `deleteFamily's bare 204 retries once on AUTH_TOKEN_EXPIRED then succeeds`() = runTest {
        authProvider.tokenAfterRefresh = "fresh-token"
        server.enqueue(
            MockResponse().setResponseCode(401)
                .setBody("""{"error":{"code":"AUTH_TOKEN_EXPIRED","message":"expired","requestId":"r_1"}}"""),
        )
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteFamily()

        assertTrue(result is ApiResult.Success)
        assertEquals(1, authProvider.forceRefreshCallCount)
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `deleteFamily forbidden for a non-parent maps to AuthForbidden`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(403).setBody(
                """{"error":{"code":"AUTH_FORBIDDEN","message":"parent only","requestId":"r_2"}}""",
            ),
        )

        val result = client.deleteFamily()

        assertTrue(result is ApiResult.Failure)
        assertTrue((result as ApiResult.Failure).error is ApiError.AuthForbidden)
    }
}
