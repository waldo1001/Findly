package com.findly.android.ui.map

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * [MapRefreshController] is the pure trigger policy of specs/010-app-shell-and-screen-ux.md §3.6
 * (rows A55/I59): WHEN the family/group map re-fetches. Driven here with `kotlinx-coroutines-test`
 * virtual time (`advanceTimeBy` + `runCurrent`, the `LocateStateHolderTest` convention — never
 * `advanceUntilIdle()`, which would race a never-ending timer loop to the end of time): the real
 * 30 s never elapses. The lifecycle wiring around it (`LifecycleResumeEffect` -> `onVisible()` /
 * `onHidden()`) is the only part not covered here; it is thin on purpose.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MapRefreshControllerTest {

    /** Records every fetch the controller makes; [gate] holds each one "in flight" until opened. */
    private class Recorder {
        val runs = mutableListOf<RefreshRun>()
        var gate: CompletableDeferred<Unit>? = null
        suspend fun fetch(run: RefreshRun) {
            runs.add(run)
            gate?.await()
        }
        val triggers: List<RefreshTrigger> get() = runs.map { it.trigger }
    }

    private fun TestScope.controller(recorder: Recorder) =
        MapRefreshController(scope = backgroundScope, fetch = recorder::fetch)

    @Test
    fun `start fetches once, immediately, with the Initial trigger`() = runTest {
        val recorder = Recorder()
        controller(recorder).start()

        runCurrent()

        assertEquals(listOf(RefreshTrigger.Initial), recorder.triggers)
    }

    @Test
    fun `the first onVisible after start is already covered by the initial load - it starts the timer, not a second fetch`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        runCurrent()

        controller.onVisible()
        runCurrent()

        assertEquals("first appearance fetches exactly once (010 §3.6 bullet 1)", listOf(RefreshTrigger.Initial), recorder.triggers)

        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(listOf(RefreshTrigger.Initial, RefreshTrigger.Timer), recorder.triggers)
    }

    @Test
    fun `the timer never fires before the screen has been visible`() = runTest {
        val recorder = Recorder()
        controller(recorder).start()
        runCurrent()

        advanceTimeBy(10 * 60_000)
        runCurrent()

        assertEquals(listOf(RefreshTrigger.Initial), recorder.triggers)
    }

    @Test
    fun `while visible the timer fetches every 30 seconds`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        assertEquals(1, recorder.runs.size)

        advanceTimeBy(29_999)
        runCurrent()
        assertEquals("not before 30 s", 1, recorder.runs.size)

        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, recorder.runs.size)

        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(3, recorder.runs.size)
        assertEquals(
            listOf(RefreshTrigger.Initial, RefreshTrigger.Timer, RefreshTrigger.Timer),
            recorder.triggers,
        )
    }

    @Test
    fun `hiding stops the timer - nothing is ever fetched in the background`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(2, recorder.runs.size)

        controller.onHidden()
        advanceTimeBy(10 * 60_000)
        runCurrent()

        assertEquals("no fetch while hidden, however long", 2, recorder.runs.size)
    }

    @Test
    fun `a return to the foreground fetches immediately and restarts the 30 second period`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        advanceTimeBy(20_000)
        controller.onHidden()
        advanceTimeBy(60_000) // 80 s in total: the old schedule would have ticked at 30 s and 60 s
        runCurrent()
        assertEquals(listOf(RefreshTrigger.Initial), recorder.triggers)

        controller.onVisible()
        runCurrent()
        assertEquals(listOf(RefreshTrigger.Initial, RefreshTrigger.Visible), recorder.triggers)

        advanceTimeBy(29_999)
        runCurrent()
        assertEquals("the period restarted at the resume, it did not resume the old one", 2, recorder.runs.size)

        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf(RefreshTrigger.Initial, RefreshTrigger.Visible, RefreshTrigger.Timer), recorder.triggers)
    }

    @Test
    fun `calling onVisible again while already visible neither double-fetches nor doubles the timer`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        controller.onVisible()
        runCurrent()
        assertEquals(1, recorder.runs.size)

        advanceTimeBy(30_000)
        runCurrent()

        assertEquals("exactly one timer fetch, not two", 2, recorder.runs.size)
    }

    @Test
    fun `a tick that arrives while a fetch is in flight is dropped, not queued`() = runTest {
        val recorder = Recorder().apply { gate = CompletableDeferred() }
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        assertEquals("the initial fetch is held in flight", 1, recorder.runs.size)

        advanceTimeBy(30_000)
        runCurrent()
        assertEquals("the 30 s tick found a fetch running and was dropped", 1, recorder.runs.size)

        recorder.gate!!.complete(Unit)
        recorder.gate = null
        runCurrent()
        assertEquals("a dropped trigger is never replayed when the running fetch ends", 1, recorder.runs.size)

        advanceTimeBy(30_000)
        runCurrent()
        assertEquals("the next tick fetches normally", 2, recorder.runs.size)
    }

    @Test
    fun `a return to the foreground while a fetch is in flight is dropped`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        controller.onHidden()
        recorder.gate = CompletableDeferred()
        controller.onVisible()
        runCurrent()
        assertEquals("the Visible fetch is now in flight", listOf(RefreshTrigger.Initial, RefreshTrigger.Visible), recorder.triggers)

        controller.onHidden()
        controller.onVisible()
        runCurrent()

        assertEquals("a second foreground return during the running fetch is dropped", 2, recorder.runs.size)
    }

    @Test
    fun `an explicit request while idle fetches and reports that it ran`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)

        val ran = controller.request(RefreshTrigger.Explicit)

        assertTrue(ran)
        assertEquals(listOf(RefreshTrigger.Explicit), recorder.triggers)
        assertTrue("an explicit Refresh reports its own failure", recorder.runs.single().explicit)
    }

    @Test
    fun `an automatic fetch is not explicit`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        runCurrent()

        assertFalse(recorder.runs.single().explicit)
    }

    @Test
    fun `an explicit request during an in-flight automatic fetch is dropped but adopts it, so its failure is reported`() = runTest {
        val recorder = Recorder().apply { gate = CompletableDeferred() }
        val controller = controller(recorder)
        controller.start()
        runCurrent()
        assertFalse("still automatic", recorder.runs.single().explicit)

        val ran = controller.request(RefreshTrigger.Explicit)

        assertFalse("not queued, not a second request", ran)
        assertEquals(1, recorder.runs.size)
        assertTrue("the running fetch now answers for the user's Refresh tap", recorder.runs.single().explicit)
    }

    // 010 §3.6 "a confirmed state change ... ends polling for that screen" (A55 review F2).

    @Test
    fun `ending polling cancels the timer - no tick ever fetches again`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(2, recorder.runs.size)

        controller.endPolling()
        advanceTimeBy(10 * 60_000)
        runCurrent()

        assertEquals("no tick after polling ended", 2, recorder.runs.size)
    }

    @Test
    fun `after polling ended a return to the foreground neither fetches nor restarts the timer`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        controller.onVisible()
        runCurrent()
        controller.endPolling()
        controller.onHidden()

        controller.onVisible()
        runCurrent()
        advanceTimeBy(10 * 60_000)
        runCurrent()

        assertEquals("only the initial fetch ever ran", listOf(RefreshTrigger.Initial), recorder.triggers)
    }

    @Test
    fun `polling ended before the first visible means the first onVisible starts nothing`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        runCurrent()
        controller.endPolling()

        controller.onVisible()
        advanceTimeBy(10 * 60_000)
        runCurrent()

        assertEquals(listOf(RefreshTrigger.Initial), recorder.triggers)
    }

    @Test
    fun `an explicit request still fetches after polling ended - the user's Retry is not polling`() = runTest {
        val recorder = Recorder()
        val controller = controller(recorder)
        controller.start()
        runCurrent()
        controller.endPolling()

        val ran = controller.request(RefreshTrigger.Explicit)

        assertTrue(ran)
        assertEquals(listOf(RefreshTrigger.Initial, RefreshTrigger.Explicit), recorder.triggers)
    }

    @Test
    fun `a fetch cancelled mid-flight reopens the gate`() = runTest {
        val recorder = Recorder().apply { gate = CompletableDeferred() }
        val controller = controller(recorder)
        val job = launch { controller.request(RefreshTrigger.Explicit) }
        runCurrent()
        assertEquals(1, recorder.runs.size)

        job.cancel()
        runCurrent()
        recorder.gate = null

        assertTrue("the next request runs - the cancelled one did not leave the gate stuck", controller.request(RefreshTrigger.Explicit))
        assertEquals(2, recorder.runs.size)
    }

    @Test
    fun `a fetch that throws reopens the gate`() = runTest {
        var calls = 0
        val controller = MapRefreshController(scope = backgroundScope) {
            calls++
            if (calls == 1) error("boom")
        }

        try {
            controller.request(RefreshTrigger.Explicit)
            fail("the fetch's exception must propagate to the caller")
        } catch (expected: IllegalStateException) {
            // propagated, as it must be - the controller does not swallow a failing fetch
        }

        assertTrue(controller.request(RefreshTrigger.Explicit))
        assertEquals(2, calls)
    }
}
