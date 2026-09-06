package com.findly.android.pushmessages

import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.1 "Android execution model": [LocateRequestHandoff.handle] is
 * what `FindlyMessagingService.onMessageReceived` calls for `LOCATE_REQUEST` instead of blocking
 * on the capture itself — it must return synchronously ([handle] is not `suspend`), and the actual
 * routing (decided by [LocateHandoffPolicy]) plus the one fast, non-blocking permission read
 * happens inside the coroutine it launches on the injected scope. */
class LocateRequestHandoffTest {

    private val data = mapOf("requestId" to "lr_1", "expiresAt" to "2026-09-06T09:06:12Z", "requestedByName" to "Eric")

    private class Recorder {
        var presenceCalls = 0
        var foregroundServiceCalls = 0
        var expeditedWorkCalls = 0
        var demotionCalls = 0
        var lastDataSeen: Map<String, String>? = null
    }

    private fun handoff(
        recorder: Recorder,
        scope: kotlinx.coroutines.CoroutineScope,
        backgroundLocationGranted: Boolean,
        presenceServiceRunning: Boolean,
    ) = LocateRequestHandoff(
        scope = scope,
        backgroundLocationGranted = { backgroundLocationGranted },
        presenceServiceRunning = { presenceServiceRunning },
        startForegroundServiceCapture = { d -> recorder.foregroundServiceCalls++; recorder.lastDataSeen = d },
        enqueueExpeditedWork = { d -> recorder.expeditedWorkCalls++; recorder.lastDataSeen = d },
        capturePresenceDirect = { d -> recorder.presenceCalls++; recorder.lastDataSeen = d },
        onDemotionDetected = { recorder.demotionCalls++ },
    )

    @Test
    fun `handle returns without waiting for the routed work to run`() = runTest {
        val recorder = Recorder()
        // A scope whose coroutines never get to run until we explicitly pump the dispatcher -
        // proves handle() itself doesn't suspend waiting on the routed branch.
        handoff(recorder, backgroundScope, backgroundLocationGranted = true, presenceServiceRunning = false)
            .handle(data, isHighPriority = true, wasDemoted = false)

        assertEquals(0, recorder.foregroundServiceCalls)
    }

    @Test
    fun `presence already running is used even at high priority with permission`() = runTest {
        val recorder = Recorder()
        handoff(recorder, backgroundScope, backgroundLocationGranted = true, presenceServiceRunning = true)
            .handle(data, isHighPriority = true, wasDemoted = false)
        runCurrent()

        assertEquals(1, recorder.presenceCalls)
        assertEquals(0, recorder.foregroundServiceCalls)
        assertEquals(0, recorder.expeditedWorkCalls)
        assertEquals(data, recorder.lastDataSeen)
    }

    @Test
    fun `high priority with background permission and no presence starts the foreground service`() = runTest {
        val recorder = Recorder()
        handoff(recorder, backgroundScope, backgroundLocationGranted = true, presenceServiceRunning = false)
            .handle(data, isHighPriority = true, wasDemoted = false)
        runCurrent()

        assertEquals(1, recorder.foregroundServiceCalls)
        assertEquals(0, recorder.presenceCalls)
        assertEquals(0, recorder.expeditedWorkCalls)
    }

    @Test
    fun `demoted priority falls back to expedited work`() = runTest {
        val recorder = Recorder()
        handoff(recorder, backgroundScope, backgroundLocationGranted = true, presenceServiceRunning = false)
            .handle(data, isHighPriority = false, wasDemoted = true)
        runCurrent()

        assertEquals(1, recorder.expeditedWorkCalls)
        assertEquals(0, recorder.foregroundServiceCalls)
    }

    @Test
    fun `missing background permission falls back to expedited work`() = runTest {
        val recorder = Recorder()
        handoff(recorder, backgroundScope, backgroundLocationGranted = false, presenceServiceRunning = false)
            .handle(data, isHighPriority = true, wasDemoted = false)
        runCurrent()

        assertEquals(1, recorder.expeditedWorkCalls)
    }

    @Test
    fun `demotion callback fires exactly when wasDemoted is true, synchronously before routing`() = runTest {
        val recorder = Recorder()
        handoff(recorder, backgroundScope, backgroundLocationGranted = true, presenceServiceRunning = false)
            .handle(data, isHighPriority = false, wasDemoted = true)

        // Fired synchronously inside handle(), not deferred to the launched coroutine.
        assertEquals(1, recorder.demotionCalls)
    }

    @Test
    fun `no demotion callback when wasDemoted is false`() = runTest {
        val recorder = Recorder()
        handoff(recorder, backgroundScope, backgroundLocationGranted = true, presenceServiceRunning = false)
            .handle(data, isHighPriority = true, wasDemoted = false)
        runCurrent()

        assertEquals(0, recorder.demotionCalls)
        assertTrue(recorder.foregroundServiceCalls == 1)
    }
}
