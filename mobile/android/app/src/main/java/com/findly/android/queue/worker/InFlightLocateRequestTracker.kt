package com.findly.android.queue.worker

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

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

    /** Returns `true` exactly once per [RequestToken] — the call that brought the shared in-flight
     * count to zero, i.e. this was the very last of all currently in-flight requests to complete.
     * Returns `false` on every other call, including a repeat call for a token that already
     * reported `true` (or `false`) once. */
    fun finish(token: RequestToken): Boolean {
        if (!token.alreadyFinished.compareAndSet(false, true)) return false
        return inFlightCount.decrementAndGet() == 0
    }

    /** Opaque per-request handle; only [InFlightLocateRequestTracker] reads its internals. */
    class RequestToken {
        internal val alreadyFinished = AtomicBoolean(false)
    }
}
