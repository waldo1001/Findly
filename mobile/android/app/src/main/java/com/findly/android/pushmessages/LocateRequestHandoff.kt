package com.findly.android.pushmessages

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * specs/009-device-runtime.md §5.1 "Android execution model": `FindlyMessagingService.onMessageReceived`
 * has roughly 10 s of guaranteed execution and MUST return immediately after handing off a
 * `LOCATE_REQUEST` rather than blocking on the capture. [handle] is deliberately **not**
 * `suspend` — it does its (synchronous, in-memory) demotion-count bookkeeping immediately, then
 * launches [scope] to do the one fast permission read and the actual routing, all of which can
 * safely happen after this method has already returned to the FCM SDK.
 *
 * The routing itself is [LocateHandoffPolicy]'s pure decision; this class only carries out
 * whichever branch it returns, via injected side-effecting lambdas so it stays testable with fakes
 * (same convention as [com.findly.android.queue.worker.ScheduleRebuilder]'s callers) instead of
 * touching `Context`/`Service`/`WorkManager` directly.
 */
class LocateRequestHandoff(
    private val scope: CoroutineScope,
    private val backgroundLocationGranted: suspend () -> Boolean,
    private val presenceServiceRunning: () -> Boolean,
    private val startForegroundServiceCapture: (Map<String, String>) -> Unit,
    private val enqueueExpeditedWork: (Map<String, String>) -> Unit,
    private val capturePresenceDirect: suspend (Map<String, String>) -> Unit,
    private val onDemotionDetected: () -> Unit = {},
) {
    fun handle(data: Map<String, String>, isHighPriority: Boolean, wasDemoted: Boolean) {
        if (wasDemoted) onDemotionDetected()

        scope.launch {
            val decision = LocateHandoffPolicy.decide(
                isHighPriority = isHighPriority,
                backgroundLocationGranted = backgroundLocationGranted(),
                presenceServiceRunning = presenceServiceRunning(),
            )
            when (decision) {
                LocateHandoffDecision.UsePresenceService -> capturePresenceDirect(data)
                LocateHandoffDecision.StartForegroundService -> startForegroundServiceCapture(data)
                LocateHandoffDecision.ExpeditedWorkManager -> enqueueExpeditedWork(data)
            }
        }
    }
}
