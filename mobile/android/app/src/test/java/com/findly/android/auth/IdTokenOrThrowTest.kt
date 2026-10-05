package com.findly.android.auth

import com.findly.android.fakes.FakeAuthProvider
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/003-android-client.md §6.5 (A52) rules 2, 3 and 4 at their single implementation,
 * `AuthProvider.idTokenOrThrow` — the one place both token-acquisition sites (the OkHttp
 * interceptor and `withAuthRetry`'s forced refresh) go through.
 */
class IdTokenOrThrowTest {

    @Test
    fun `returns the provider's token and signs nobody out`() = runTest {
        val provider = FakeAuthProvider(initialToken = "tok-1")

        assertEquals("tok-1", provider.idTokenOrThrow())
        assertEquals(0, provider.signOutCallCount)
    }

    @Test
    fun `a signed-out provider yields null, not a failure`() = runTest {
        val provider = FakeAuthProvider(initialToken = null, initialState = AuthState.SignedOut)

        assertNull(provider.idTokenOrThrow())
        assertEquals(0, provider.signOutCallCount)
    }

    @Test
    fun `forceRefresh is forwarded to the provider`() = runTest {
        val provider = FakeAuthProvider(initialToken = "old").apply { tokenAfterRefresh = "new" }

        assertEquals("new", provider.idTokenOrThrow(forceRefresh = true))
        assertEquals(1, provider.forceRefreshCallCount)
    }

    @Test
    fun `UserInvalid signs the user out exactly once and is rethrown as the same instance`() = runTest {
        val failure = IdTokenException.UserInvalid(IllegalStateException("user record deleted"))
        val provider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1")).apply { tokenFailure = failure }

        val thrown = runCatching { provider.idTokenOrThrow() }.exceptionOrNull()

        assertSame(failure, thrown)
        assertEquals("a deleted/disabled user must be signed out locally", 1, provider.signOutCallCount)
        assertEquals(AuthState.SignedOut, provider.authState.value)
    }

    @Test
    fun `UserInvalid also signs out when it is the forced refresh that fails`() = runTest {
        val provider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-1"))
            .apply { refreshFailure = IdTokenException.UserInvalid() }

        val thrown = runCatching { provider.idTokenOrThrow(forceRefresh = true) }.exceptionOrNull()

        assertTrue(thrown is IdTokenException.UserInvalid)
        assertEquals(1, provider.signOutCallCount)
    }

    @Test
    fun `UserInvalid for a user who is no longer the signed-in one does not sign out the new user`() = runTest {
        val provider = FakeAuthProvider(initialState = AuthState.SignedIn("uid-A")).apply {
            tokenFailure = IdTokenException.UserInvalid()
            // While A's fetch is in flight, B signs in.
            onTokenFetch = { setAuthState(AuthState.SignedIn("uid-B")) }
        }

        val thrown = runCatching { provider.idTokenOrThrow() }.exceptionOrNull()

        assertTrue(thrown is IdTokenException.UserInvalid)
        assertEquals("a late failure for A must never sign out B", 0, provider.signOutCallCount)
        assertEquals(AuthState.SignedIn("uid-B"), provider.authState.value)
    }

    @Test
    fun `UserInvalid when already signed out does not sign out again`() = runTest {
        val provider = FakeAuthProvider(initialState = AuthState.SignedOut).apply {
            tokenFailure = IdTokenException.UserInvalid()
        }

        val thrown = runCatching { provider.idTokenOrThrow() }.exceptionOrNull()

        assertTrue(thrown is IdTokenException.UserInvalid)
        assertEquals(0, provider.signOutCallCount)
    }

    @Test
    fun `Transient is rethrown untouched and never signs out`() = runTest {
        val failure = IdTokenException.Transient(IOException("offline"))
        val provider = FakeAuthProvider().apply { tokenFailure = failure }

        val thrown = runCatching { provider.idTokenOrThrow() }.exceptionOrNull()

        assertSame(failure, thrown)
        assertEquals("a transient failure must NOT sign the user out", 0, provider.signOutCallCount)
        assertEquals(AuthState.SignedIn("uid-test"), provider.authState.value)
    }

    @Test
    fun `any other exception from a provider is normalised to Transient with the cause kept`() = runTest {
        val raw = IllegalStateException("some SDK exception nobody mapped")
        val provider = FakeAuthProvider().apply { tokenFailure = raw }

        val thrown = runCatching { provider.idTokenOrThrow() }.exceptionOrNull()

        assertTrue("was $thrown", thrown is IdTokenException.Transient)
        assertSame(raw, thrown!!.cause)
        assertEquals(0, provider.signOutCallCount)
    }

    @Test
    fun `a CancellationException raised under an active caller is a failed fetch - Transient, not a cancellation`() = runTest {
        // What a cancelled Play-services Task looks like: a CancellationException the CALLER did not
        // cause. Letting it propagate would silently end a coroutine that was never cancelled
        // (e.g. the launch gate's authState collector) - so it must be a failure, like any other.
        val foreign = CancellationException("Task was cancelled")
        val provider = FakeAuthProvider().apply { tokenFailure = foreign }

        val thrown = runCatching { provider.idTokenOrThrow() }.exceptionOrNull()

        assertTrue("was $thrown", thrown is IdTokenException.Transient)
        assertSame(foreign, thrown!!.cause)
        assertEquals(0, provider.signOutCallCount)
    }

    @Test
    fun `the calling coroutine's own cancellation still propagates unconverted and signs nobody out`() = runTest {
        val fetchStarted = CompletableDeferred<Unit>()
        val fake = FakeAuthProvider()
        val provider = object : AuthProvider by fake {
            override suspend fun currentIdToken(forceRefresh: Boolean): String? {
                fetchStarted.complete(Unit)
                awaitCancellation()
            }
        }
        var outcome: Result<String?>? = null
        val caller = launch { outcome = runCatching { provider.idTokenOrThrow() } }

        fetchStarted.await()
        caller.cancel()
        caller.join()

        val thrown = outcome!!.exceptionOrNull()
        assertTrue("a genuine cancellation must propagate as one, was $thrown", thrown is CancellationException)
        assertEquals(0, fake.signOutCallCount)
    }
}
