package com.findly.android.network

import com.findly.android.auth.IdTokenException
import com.findly.android.fakes.FakeAuthProvider
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/**
 * specs/003-android-client.md §6.5 (A52): obtaining the ID token must never crash the process.
 *
 * The crash this reproduces (Pixel 9 Pro Fold, 2026-10-05): a throwing token source made OkHttp 4.12's
 * `RealCall.AsyncCall.run` report a synthetic "canceled" `IOException` to the callback **and rethrow
 * the original on the dispatcher thread** — on Android, a process kill. [uncaughtOnDispatcher] is
 * how these tests see that second half, which a callback-only assertion would miss.
 */
class AuthInterceptorTest {

    private lateinit var server: MockWebServer
    private lateinit var dispatcherThreads: CopyOnWriteArrayList<Thread>
    private lateinit var uncaughtOnDispatcher: CopyOnWriteArrayList<Throwable>
    private lateinit var executor: ThreadPoolExecutor

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
        server.enqueue(MockResponse().setResponseCode(200).setBody("{}"))

        dispatcherThreads = CopyOnWriteArrayList()
        uncaughtOnDispatcher = CopyOnWriteArrayList()
        // What Android's default handler would do — here, record instead of dying.
        executor = ThreadPoolExecutor(0, Int.MAX_VALUE, 60, TimeUnit.SECONDS, LinkedBlockingQueue()) { runnable ->
            Thread(runnable, "test-okhttp-dispatcher").apply {
                setUncaughtExceptionHandler { _, e -> uncaughtOnDispatcher.add(e) }
                dispatcherThreads.add(this)
            }
        }
    }

    @After
    fun tearDown() {
        server.shutdown()
        executor.shutdownNow()
    }

    private fun clientFor(authProvider: FakeAuthProvider): OkHttpClient = OkHttpClient.Builder()
        .dispatcher(Dispatcher(executor))
        .addInterceptor(AuthInterceptor(authProvider))
        .build()

    private fun request(): Request = Request.Builder().url(server.url("/api/v1/families/me")).build()

    /** Waits until every dispatcher thread has fully terminated, so a rethrown exception has
     * demonstrably reached [uncaughtOnDispatcher] (or demonstrably has not). */
    private fun drainDispatcher() {
        executor.shutdown()
        assertTrue("dispatcher did not drain", executor.awaitTermination(10, TimeUnit.SECONDS))
        dispatcherThreads.forEach { it.join(10_000) }
    }

    /** Every way a token source can fail: raw non-IOExceptions (what an unmapped SDK exception looks
     * like to OkHttp — the actual defect), and the two project-defined kinds. */
    private fun failingSources(): List<Throwable> = listOf(
        IllegalStateException("There is no user record corresponding to this identifier."),
        RuntimeException("FirebaseNetworkException stand-in"),
        // A cancelled Play-services Task surfaces as a CancellationException (an IllegalStateException
        // subclass) that idTokenOrThrow deliberately does not absorb — the interceptor, which has no
        // coroutine to cancel, must still contain it.
        CancellationException("Task was cancelled"),
        IdTokenException.Transient(IOException("offline")),
        IdTokenException.UserInvalid(IllegalStateException("user deleted")),
    )

    // --- the happy path (behaviour that must not regress) -------------------------------------

    @Test
    fun `attaches the bearer token to the request`() {
        val client = clientFor(FakeAuthProvider(initialToken = "tok-123"))

        client.newCall(request()).execute().use { assertEquals(200, it.code) }

        assertEquals("Bearer tok-123", server.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun `a null token - signed out - sends the request without an Authorization header`() {
        val client = clientFor(FakeAuthProvider(initialToken = null))

        client.newCall(request()).execute().use { assertEquals(200, it.code) }

        assertNull(server.takeRequest().getHeader("Authorization"))
    }

    // --- §6.5 rule 1: only an IOException may leave the interceptor ---------------------------

    @Test
    fun `a failing token source surfaces from execute as an IOException and sends no request`() {
        for (failure in failingSources()) {
            val client = clientFor(FakeAuthProvider().apply { tokenFailure = failure })

            val thrown = runCatching { client.newCall(request()).execute() }.exceptionOrNull()

            assertTrue("$failure must surface as an IOException, was $thrown", thrown is IOException)
            assertFalse("$failure must not leak as a RuntimeException", thrown is RuntimeException)
        }
        assertEquals("no request may be sent without a token", 0, server.requestCount)
    }

    @Test
    fun `a failing token source on the async path reaches onFailure and never kills the dispatcher thread`() {
        for (failure in failingSources()) {
            val client = clientFor(FakeAuthProvider().apply { tokenFailure = failure })
            val failed = CountDownLatch(1)
            val delivered = CopyOnWriteArrayList<IOException>()

            client.newCall(request()).enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    delivered.add(e)
                    failed.countDown()
                }

                override fun onResponse(call: Call, response: Response) {
                    response.close()
                    fail("the request must not be sent when no token can be obtained")
                }
            })
            assertTrue("onFailure never arrived for $failure", failed.await(10, TimeUnit.SECONDS))
            assertEquals(1, delivered.size)
        }
        drainDispatcher()

        assertTrue(
            "an exception was rethrown on the OkHttp dispatcher thread — on Android this kills the " +
                "process: $uncaughtOnDispatcher",
            uncaughtOnDispatcher.isEmpty(),
        )
        assertEquals(0, server.requestCount)
    }

    @Test
    fun `the project-defined failure kinds reach the caller intact so the client can tell them apart`() {
        val userInvalid = IdTokenException.UserInvalid()
        val transient = IdTokenException.Transient()

        val thrownUserInvalid = runCatching {
            clientFor(FakeAuthProvider().apply { tokenFailure = userInvalid }).newCall(request()).execute()
        }.exceptionOrNull()
        val thrownTransient = runCatching {
            clientFor(FakeAuthProvider().apply { tokenFailure = transient }).newCall(request()).execute()
        }.exceptionOrNull()

        assertTrue("was $thrownUserInvalid", thrownUserInvalid is IdTokenException.UserInvalid)
        assertTrue("was $thrownTransient", thrownTransient is IdTokenException.Transient)
    }
}
