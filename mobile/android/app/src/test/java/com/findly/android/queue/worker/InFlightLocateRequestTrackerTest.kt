package com.findly.android.queue.worker

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * docs/implementation-handoff.md A44 (specs/009-device-runtime.md §5.1): `LocateForegroundService`
 * is a singleton, so two genuinely overlapping same-device `LOCATE_REQUEST`s can be in flight on
 * the one instance at once. `finish()`'s `stopForeground(STOP_FOREGROUND_DETACH)` used to run
 * unconditionally on every request's completion — detaching the service's OS foreground
 * designation as soon as the *first* of two overlapping requests finished, while the second was
 * still capturing. This is the pure decidable part of the fix (same bucket as
 * [LocateHandoffPolicy] / `PushMessageLanePolicy`): the service holds one
 * [InFlightLocateRequestTracker] instance and asks it whether a given completion was the *last*
 * one in flight, rather than deciding that inline.
 *
 * `finish()` is called from both a per-request timeout coroutine and the capture coroutine's
 * `finally` block, racing on `Dispatchers.Default` worker threads — genuinely concurrent, not
 * just interleaved — so both the shared count and each request's own completed-once guard are
 * built on atomics, never a plain `Int`/`Boolean` that assumes serialized callbacks.
 */
class InFlightLocateRequestTrackerTest {

    @Test
    fun `a single request detaches on its own completion`() {
        val tracker = InFlightLocateRequestTracker()
        val token = tracker.start()

        assertTrue(tracker.finish(token))
    }

    @Test
    fun `the first of two overlapping requests to finish does not detach`() {
        val tracker = InFlightLocateRequestTracker()
        val first = tracker.start()
        tracker.start() // second request still in flight

        assertFalse(tracker.finish(first))
    }

    @Test
    fun `the last of two overlapping requests to finish does detach`() {
        val tracker = InFlightLocateRequestTracker()
        val first = tracker.start()
        val second = tracker.start()

        tracker.finish(first)

        assertTrue(tracker.finish(second))
    }

    @Test
    fun `detach depends on completion order, not start order`() {
        val tracker = InFlightLocateRequestTracker()
        val first = tracker.start()
        val second = tracker.start()

        // second (started later) finishes first - still not the last in flight.
        assertFalse(tracker.finish(second))
        // first (started earlier) finishes last - it's the one that detaches.
        assertTrue(tracker.finish(first))
    }

    @Test
    fun `finishing the same token twice only decrements once - second call reports not-last`() {
        val tracker = InFlightLocateRequestTracker()
        val first = tracker.start()
        tracker.start() // second request still in flight

        assertFalse(tracker.finish(first))
        // Repeat completion for the same token (the timeout-vs-capture race both firing for one
        // request) must not double-decrement the shared count.
        assertFalse(tracker.finish(first))
    }

    @Test
    fun `a repeated finish never reports last, even after the real last completion already ran`() {
        val tracker = InFlightLocateRequestTracker()
        val token = tracker.start()

        assertTrue(tracker.finish(token))
        // A stale second call for the same request (e.g. its orphaned timeout job firing after
        // its capture already completed) must not report "last" again.
        assertFalse(tracker.finish(token))
    }

    @Test
    fun `three overlapping requests - only the third completion detaches`() {
        val tracker = InFlightLocateRequestTracker()
        val a = tracker.start()
        val b = tracker.start()
        val c = tracker.start()

        assertFalse(tracker.finish(a))
        assertFalse(tracker.finish(b))
        assertTrue(tracker.finish(c))
    }

    @Test
    fun `concurrent completions - exactly one of many overlapping requests reports last`() {
        val tracker = InFlightLocateRequestTracker()
        val requestCount = 50
        val tokens = (1..requestCount).map { tracker.start() }

        // One thread per task: every task must be able to reach `startLatch.await()` before any
        // of them is released, so the pool must never be smaller than requestCount - a smaller
        // pool would let already-running tasks block on startLatch while queued tasks can never
        // get a thread to signal readyLatch from, which just wastes wall-clock time (not a false
        // pass) sitting out readyLatch's own timeout before this test's later countDown unblocks
        // things anyway.
        val executor = Executors.newFixedThreadPool(requestCount)
        val readyLatch = CountDownLatch(requestCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(requestCount)
        val lastCount = AtomicInteger(0)

        tokens.forEach { token ->
            executor.submit {
                readyLatch.countDown()
                startLatch.await()
                if (tracker.finish(token)) lastCount.incrementAndGet()
                doneLatch.countDown()
            }
        }

        readyLatch.await(5, TimeUnit.SECONDS)
        startLatch.countDown() // release every thread at once to force real concurrency
        assertTrue(doneLatch.await(5, TimeUnit.SECONDS))
        executor.shutdown()

        assertEquals(1, lastCount.get())
    }

    // --- A48 (docs/implementation-handoff.md; specs/009-device-runtime.md §5.1): `timeoutJob` in
    // `LocateForegroundService` used to be a single `@Volatile` field shared by every request on
    // the singleton service, not a per-request value. A second request's `onStartCommand` running
    // while a first was still in flight overwrote that field; a later `finish()` for the *first*
    // request then cancelled whichever job the field currently held, which could be the *second*
    // request's own 45s hard-cap timeout — the wrong request could lose its cap while the other
    // was cancelled early. The fix moves the timeout `Job` into `RequestToken` itself (it already
    // exists per request, same as the in-flight-count bookkeeping this class already does), so
    // `finish(token)` can only ever cancel *that token's own* job, structurally, not by convention.

    @Test
    fun `finish cancels only its own request's timeout job, not another overlapping request's`() {
        val tracker = InFlightLocateRequestTracker()
        val first = tracker.start()
        val second = tracker.start() // second request's onStartCommand ran while first still in flight

        val firstTimeoutJob = Job()
        val secondTimeoutJob = Job()
        tracker.attachTimeoutJob(first, firstTimeoutJob)
        tracker.attachTimeoutJob(second, secondTimeoutJob)

        // first's capture finishes (or its own timeout fires) - this must not touch second's timer.
        tracker.finish(first)

        assertTrue("finish(first) must cancel first's own timeout job", firstTimeoutJob.isCancelled)
        assertFalse(
            "finish(first) must NOT cancel second's still-in-flight timeout job - this is exactly " +
                "the A48 defect: a shared field let one request's completion cancel a different " +
                "request's 45s hard cap",
            secondTimeoutJob.isCancelled,
        )
    }

    @Test
    fun `finish cancels the correct job regardless of which overlapping request completes first`() {
        val tracker = InFlightLocateRequestTracker()
        val first = tracker.start()
        val second = tracker.start()

        val firstTimeoutJob = Job()
        val secondTimeoutJob = Job()
        tracker.attachTimeoutJob(first, firstTimeoutJob)
        tracker.attachTimeoutJob(second, secondTimeoutJob)

        // second (started later) finishes first this time.
        tracker.finish(second)

        assertTrue(secondTimeoutJob.isCancelled)
        assertFalse(
            "second finishing first must not cancel first's still-in-flight timeout job",
            firstTimeoutJob.isCancelled,
        )
    }

    @Test
    fun `finish is idempotent about cancelling its own token's timeout job across a repeated call`() {
        val tracker = InFlightLocateRequestTracker()
        val token = tracker.start()
        val timeoutJob = Job()
        tracker.attachTimeoutJob(token, timeoutJob)

        // The documented timeout-vs-capture race: finish() runs twice for one logical request.
        tracker.finish(token)
        tracker.finish(token) // must not throw, and must remain cancelled

        assertTrue(timeoutJob.isCancelled)
    }

    @Test
    fun `a request with no attached timeout job still finishes without error`() {
        // Defensive: attachTimeoutJob is called once, synchronously, right after the timeout
        // coroutine is launched in real usage, but finish() must not NPE if it is somehow called
        // before that assignment lands.
        val tracker = InFlightLocateRequestTracker()
        val token = tracker.start()

        assertTrue(tracker.finish(token))
    }

    @Test
    fun `concurrent completions of many overlapping requests each cancel only their own timeout job`() {
        val tracker = InFlightLocateRequestTracker()
        val requestCount = 50
        val tokens = (1..requestCount).map { tracker.start() }
        val timeoutJobs = tokens.map { token ->
            Job().also { tracker.attachTimeoutJob(token, it) }
        }

        // Same forced-concurrency shape as the test above: every thread must reach startLatch
        // before any is released, so finish() calls for different tokens genuinely race on
        // different Dispatchers.Default-like worker threads, not merely interleave.
        val executor = Executors.newFixedThreadPool(requestCount)
        val readyLatch = CountDownLatch(requestCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(requestCount)

        tokens.forEachIndexed { index, token ->
            executor.submit {
                readyLatch.countDown()
                startLatch.await()
                tracker.finish(token)
                doneLatch.countDown()
            }
        }

        readyLatch.await(5, TimeUnit.SECONDS)
        startLatch.countDown()
        assertTrue(doneLatch.await(5, TimeUnit.SECONDS))
        executor.shutdown()

        timeoutJobs.forEachIndexed { index, job ->
            assertTrue("timeout job for request $index was never cancelled by its own finish()", job.isCancelled)
        }
    }
}
