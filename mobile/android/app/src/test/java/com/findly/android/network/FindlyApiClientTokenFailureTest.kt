package com.findly.android.network

import com.findly.android.auth.AuthState
import com.findly.android.auth.IdTokenException
import com.findly.android.fakes.FakeAuthProvider
import java.io.IOException
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
 * specs/003-android-client.md §6.5 (A52), end to end through the real Retrofit/OkHttp/
 * `AuthInterceptor` stack against a [MockWebServer] — what the caller of a `FindlyApiClient` method
 * actually sees when the ID token cannot be obtained:
 *
 * - rule 3: Firebase says the user is invalid → local sign-out (once) + `Failure(AuthInvalidToken)`,
 *   a *confirmed* auth failure for 010 §1.1 / A37;
 * - rule 4: anything else → `Failure(NetworkFailure)`, **no** sign-out;
 * - rule 5: identical on every `IOException`-catching path and when the §6.4 forced refresh is the
 *   call that fails.
 */
class FindlyApiClientTokenFailureTest {

    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    private fun clientFor(authProvider: FakeAuthProvider): FindlyApiClient =
        FindlyApiClient(RetrofitFactory.create(server.url("/").toString(), authProvider), authProvider)

    private val expiredBody = """{"error":{"code":"AUTH_TOKEN_EXPIRED","message":"expired","requestId":"r_1"}}"""

    /** One entry per `IOException`-catching path in `FindlyApiClient` (§6.5 rule 5): the generic
     * envelope, the bare 204, the bare 304, the ETag-carrying success, and the unenveloped export. */
    private val everyCatchSite: List<Pair<String, suspend (FindlyApiClient) -> ApiResult<*>>> = listOf(
        "getMyFamily (envelope)" to { c -> c.getMyFamily() },
        "removeMember (bare 204)" to { c -> c.removeMember("u2") },
        "getGeofences (bare 304)" to { c -> c.getGeofences(ifNoneMatch = "\"0x1\"") },
        "replaceGeofences (ETag success)" to { c -> c.replaceGeofences(ifMatch = "\"0x1\"", geofences = emptyList()) },
        "exportData (unenveloped)" to { c -> c.exportData() },
    )

    // --- rule 3: user invalid ------------------------------------------------------------------

    @Test
    fun `a user Firebase reports invalid is signed out once and surfaces as a confirmed AuthInvalidToken`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
            tokenFailure = IdTokenException.UserInvalid(IllegalStateException("There is no user record"))
        }

        val result = clientFor(authProvider).getMyFamily()

        assertTrue("was $result", result is ApiResult.Failure)
        val error = (result as ApiResult.Failure).error
        assertTrue("was $error", error is ApiError.AuthInvalidToken)
        assertNull("client-synthesized: there is no response, so no requestId", error.requestId)
        assertEquals("exactly one local sign-out", 1, authProvider.signOutCallCount)
        assertEquals(AuthState.SignedOut, authProvider.authState.value)
        assertEquals("the request must not be sent", 0, server.requestCount)
    }

    @Test
    fun `UserInvalid is AuthInvalidToken on every path that catches an IOException`() = runTest {
        for ((name, call) in everyCatchSite) {
            val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
                tokenFailure = IdTokenException.UserInvalid()
            }

            val result = call(clientFor(authProvider))

            assertTrue("$name: was $result", result is ApiResult.Failure && result.error is ApiError.AuthInvalidToken)
            assertEquals("$name: one sign-out", 1, authProvider.signOutCallCount)
        }
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `a failing forced refresh after AUTH_TOKEN_EXPIRED for a deleted user signs out and is AuthInvalidToken`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
            refreshFailure = IdTokenException.UserInvalid()
        }
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))

        val result = clientFor(authProvider).getMyFamily()

        assertTrue("was $result", result is ApiResult.Failure && result.error is ApiError.AuthInvalidToken)
        assertEquals(1, authProvider.signOutCallCount)
        assertEquals("no retry once the refresh failed", 1, server.requestCount)
    }

    // --- rule 4: transient ---------------------------------------------------------------------

    @Test
    fun `a transient token failure is a NetworkFailure and does not sign out`() = runTest {
        val cause = IOException("offline")
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
            tokenFailure = IdTokenException.Transient(cause)
        }

        val result = clientFor(authProvider).getMyFamily()

        assertTrue("was $result", result is ApiResult.Failure)
        val error = (result as ApiResult.Failure).error
        assertTrue("was $error", error is ApiError.NetworkFailure)
        assertEquals(0, authProvider.signOutCallCount)
        assertEquals(AuthState.SignedIn("uid-1"), authProvider.authState.value)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `a raw exception from a provider is treated as transient - NetworkFailure, no sign-out`() = runTest {
        val authProvider = FakeAuthProvider().apply { tokenFailure = IllegalStateException("unmapped SDK failure") }

        val result = clientFor(authProvider).getMyFamily()

        assertTrue("was $result", result is ApiResult.Failure && result.error is ApiError.NetworkFailure)
        assertEquals(0, authProvider.signOutCallCount)
    }

    @Test
    fun `Transient is NetworkFailure on every path that catches an IOException`() = runTest {
        for ((name, call) in everyCatchSite) {
            val authProvider = FakeAuthProvider().apply { tokenFailure = IdTokenException.Transient() }

            val result = call(clientFor(authProvider))

            assertTrue("$name: was $result", result is ApiResult.Failure && result.error is ApiError.NetworkFailure)
            assertEquals("$name: no sign-out", 0, authProvider.signOutCallCount)
        }
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `a failing forced refresh after AUTH_TOKEN_EXPIRED while offline is a NetworkFailure, not a sign-out`() = runTest {
        val authProvider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply {
            refreshFailure = IdTokenException.Transient(IOException("offline"))
        }
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))

        val result = clientFor(authProvider).getMyFamily()

        // Surfacing the original AuthTokenExpired here would be wrong: 010 §1.1 treats it as a
        // confirmed auth failure and signs the user out — for a user who is merely offline.
        assertTrue("was $result", result is ApiResult.Failure && result.error is ApiError.NetworkFailure)
        assertEquals(0, authProvider.signOutCallCount)
        assertEquals(1, server.requestCount)
    }

    @Test
    fun `a raw exception thrown by the forced refresh is contained as a NetworkFailure`() = runTest {
        val authProvider = FakeAuthProvider().apply { refreshFailure = IllegalStateException("unmapped SDK failure") }
        server.enqueue(MockResponse().setResponseCode(401).setBody(expiredBody))

        val result = clientFor(authProvider).getMyFamily()

        assertTrue("was $result", result is ApiResult.Failure && result.error is ApiError.NetworkFailure)
        assertEquals(0, authProvider.signOutCallCount)
    }
}
