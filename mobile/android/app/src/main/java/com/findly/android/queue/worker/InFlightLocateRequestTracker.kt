package com.findly.android.queue.worker

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Job

/**
 * docs/implementation-handoff.md A44 (specs/009-device-runtime.md §5.1): [LocateForegroundService]
 * is a singleton, so two genuinely overlapping same-device `LOCATE_REQUEST`s can be in flight on
 * the one instance at once. Before this class existed, `finish()`'s
 * `stopForeground(STOP_FOREGROUND_DETACH)` ran unconditionally on every request's completion —
 * detaching the service's OS foreground designation as soon as the *first* of two overlapping
 * requests finished, while the second was still capturing. This is the pure decidable part of the
 * fix, extracted the same way [LocateHandoffPolicy] and
 * [com.findly.android.pushmessages.PushMessageLanePolicy] extract the decidable part out of
 * otherwise-untestable `Service`/framework glue: the service holds one instance of this tracker
 * and asks it whether a given completion was the *last* one currently in flight, rather than
 * deciding that inline.
 *
 * This is a **bounded priority dip, not data loss and not a notification-content bug** — A39
 * already scoped the locate notification id per `requestId` ([LocateNotificationId]), so every
 * in-flight request keeps its own notification and both captures still fulfil regardless of this
 * fix; only the service's OS foreground designation could drop a few seconds early for the request
 * still running.
 *
 * Thread-safe by construction, not by assumption: [LocateForegroundService.finish] is called from
 * both a per-request timeout coroutine and the capture coroutine's `finally` block, racing on
 * `Dispatchers.Default` worker threads for *different* overlapping requests at once — genuinely
 * concurrent, not merely interleaved. [inFlightCount] is an [AtomicInteger] rather than a plain
 * `Int`, and each [RequestToken]'s own [RequestToken.alreadyFinished] guard is an [AtomicBoolean]
 * compare-and-set rather than a plain `Boolean`.
 *
 * Additive, not redundant, alongside `stopSelf(startId)`: Android's `stopSelf(Int)` already
 * prevents the *service process* from being killed out from under a second in-flight request
 * (`stopSelf(startId)` is a no-op once a more recent `startId` has been delivered) — that is a
 * different, already-correct guarantee about the service's *existence*. Nothing about `stopSelf`
 * semantics constrains `stopForeground`, which this class exists to gate: `finish()` called
 * `stopForeground(STOP_FOREGROUND_DETACH)` unconditionally, with no dependency on `startId`
 * recency at all, so the OS foreground *designation* could still be dropped by the first
 * completion even though the process itself correctly stayed alive.
 *
 * **A48 (docs/implementation-handoff.md; found by A44, reported rather than folded in):**
 * [LocateForegroundService.timeoutJob] used to be a single `@Volatile` field on the *service*,
 * shared by every request, not a per-request value. A second request's `onStartCommand` running
 * while a first was still in flight overwrote that field with the second request's own timeout
 * `Job`; a later `finish()` for the *first* request then cancelled whichever job the field
 * currently held — which could be the *second* request's still-legitimately-running 45s hard cap.
 * Consequence: the timeout cap could be applied to the wrong request, entirely independent of the
 * in-flight-count/foreground-designation bug A44 fixed above. The fix follows the same shape as
 * [inFlightCount]: [RequestToken] already exists one-per-request, so the timeout `Job` is stored
 * on it ([RequestToken.timeoutJob], via [attachTimeoutJob]) rather than in a second parallel
 * per-service field. [finish] then cancels only the calling token's own job, which is correct *by
 * construction* — there is no shared field left for a different request's completion to reach.
 * [RequestToken.timeoutJob] is an [AtomicReference] for the same reason [inFlightCount] is an
 * [AtomicInteger]: [attachTimeoutJob] is written from the main thread ([LocateForegroundService
 * .onStartCommand]) while [finish] reads and cancels it from `Dispatchers.Default` worker threads,
 * for potentially many overlapping requests, at once.
 */
class InFlightLocateRequestTracker {
    private val inFlightCount = AtomicInteger(0)

    /** Call once per request, when it starts (`onStartCommand`). Returns a token identifying this
     * request's own completion — pass it to [finish], possibly more than once for the same
     * request (the existing timeout-vs-capture race, see [LocateForegroundService.finish]'s own
     * "idempotent" doc): [finish] decrements the shared count exactly once per token no matter how
     * many times it is called with that token. */
    fun start(): RequestToken {
        inFlightCount.incrementAndGet()
        return RequestToken()
    }

    /** A48: associates [job] — this request's own 45s hard-cap timeout coroutine — with [token],
     * so a later [finish] call for a *different* overlapping request's token can never reach it.
     * Call once, synchronously, immediately after launching the timeout coroutine and before
     * launching the capture coroutine that shares [token] — [LocateForegroundService
     * .onStartCommand] does both on the calling (main) thread with no suspension in between, so
     * the write is guaranteed to land before either coroutine's body could possibly call [finish]
     * for this token. [AtomicReference.set] gives the required cross-thread visibility for that
     * write to be seen correctly by whichever worker thread calls [finish] later. */
    fun attachTimeoutJob(token: RequestToken, job: Job) {
        token.timeoutJob.set(job)
    }

    /** Returns `true` exactly once per [RequestToken] — the call that brought the shared in-flight
     * count to zero, i.e. this was the very last of all currently in-flight requests to complete.
     * Returns `false` on every other call, including a repeat call for a token that already
     * reported `true` (or `false`) once.
     *
     * A48: also cancels [token]'s own attached timeout job, every time this is called (not only
     * the first) — `Job.cancel()` is idempotent and safe to call from multiple threads, and the
     * documented timeout-vs-capture race means either coroutine can be the one that gets here
     * first for a given token. Cancelling here can never affect a *different* token's job: there
     * is no shared field to race on any more, only this token's own [RequestToken.timeoutJob]. */
    fun finish(token: RequestToken): Boolean {
        token.timeoutJob.get()?.cancel()
        if (!token.alreadyFinished.compareAndSet(false, true)) return false
        return inFlightCount.decrementAndGet() == 0
    }

    /** Opaque per-request handle; only [InFlightLocateRequestTracker] reads its internals. */
    class RequestToken {
        internal val alreadyFinished = AtomicBoolean(false)

        /** A48: this request's own 45s hard-cap timeout [Job], set once via [attachTimeoutJob].
         * `null` until then (or if a request never gets one attached, defensively — [finish] must
         * not fail just because this happens to still be unset). */
        internal val timeoutJob = AtomicReference<Job?>(null)
    }
}
