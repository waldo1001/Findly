package com.findly.android.ui.map

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * [fetchGuarded] (specs/010 §3.6 hardening, A55): a background timer repeats the roster `GET` every
 * 30 s for as long as the map is open, on a scope with no `CoroutineExceptionHandler`
 * (`viewModelScope`) — so an exception the API client lets escape (`FindlyApiClient` only turns an
 * `IOException` into an `ApiResult.Failure`; a `SerializationException` from a 200 with a malformed
 * body — a captive-portal page — is not one) would kill the process within 30 s of sitting on the
 * map. A throw is a transport-class failure instead; cancellation must still pass through.
 */
class GuardedFetchTest {

    @Test
    fun `a normal result passes through untouched`() = runTest {
        val ok = ApiResult.Success("roster", features = null)

        assertSame(ok, fetchGuarded { ok })
    }

    @Test
    fun `an ordinary exception becomes a NetworkFailure carrying it`() = runTest {
        val boom = IllegalStateException("malformed body")

        val result = fetchGuarded<String> { throw boom }

        assertTrue(result is ApiResult.Failure)
        val error = (result as ApiResult.Failure).error
        assertTrue("expected a transport-class failure, was $error", error is ApiError.NetworkFailure)
        assertSame(boom, (error as ApiError.NetworkFailure).cause)
    }

    @Test
    fun `cancellation is never swallowed`() = runTest {
        try {
            fetchGuarded<String> { throw CancellationException("scope cleared") }
            fail("a CancellationException must propagate so structured concurrency still cancels")
        } catch (expected: CancellationException) {
            assertEquals("scope cleared", expected.message)
        }
    }
}
