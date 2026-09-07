package com.findly.android.queue.worker

import android.content.Intent
import android.os.IBinder
import android.util.Log
import android.app.Service
import androidx.core.app.NotificationManagerCompat
import com.findly.android.FindlyApplication
import com.findly.android.pushmessages.LocateNotifier
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * specs/009-device-runtime.md §5.1's short-lived `FOREGROUND_SERVICE_LOCATION` service for a
 * non-demoted (`PRIORITY_HIGH`) `LOCATE_REQUEST` with `ACCESS_BACKGROUND_LOCATION` granted —
 * started only via [com.findly.android.pushmessages.LocateRequestHandoff]
 * (`LocateHandoffDecision.StartForegroundService`), never called directly elsewhere. Posts the
 * `findly_locate` notification via the shared [LocateNotifier] (A39 review, finding 1 — every
 * handoff branch must post it, not just this one) and reuses that same notification as its own
 * foreground notification — a single object satisfies both the OS requirement and the
 * user-visible design goal. All the actual capture/fulfil logic is the same tested
 * [com.findly.android.pushmessages.LocateRequestPushHandler] the presence-reuse and WorkManager
 * paths also call — nothing about the capture is duplicated here. Thin, untested Android-framework
 * glue by design (same bucket as [LocationForegroundService]).
 *
 * Hard cap: 45 s (§5.1), then `stopSelf()` regardless of whether the capture finished — never
 * `START_STICKY` (a one-shot service must not be resurrected by the OS after being killed).
 *
 * **A39 review, finding 2:** [serviceScope] carries a [CoroutineExceptionHandler] so an uncaught
 * throw from the capture (`AppContainer` construction — Room open, Firebase init — the device-id
 * provider's auth/prefs read, or the battery-level read are all live sources on a cold
 * FCM-started process) logs and stops this one capture rather than crashing the whole process; the
 * `finally` below still always runs first.
 *
 * **A42 (docs/implementation-handoff.md) sweep, finding 5:** [exceptionHandler] used to log the
 * raw `throwable` (`Log.w(TAG, "...", throwable)`), which prints its full message and stack trace —
 * a location/Retrofit exception's message routinely embeds exactly what specs/009-device-runtime.md
 * §9 forbids logging (coordinates, `deviceId`, tokens, phone numbers). Fixed to log the exception's
 * class name only, matching every other handler this sweep added/audited.
 *
 * **A39 review, finding 3:** `startForeground` itself is guarded — a start that lost its FCM
 * background-start exemption (API 31+), or a `location`-typed FGS whose permission was revoked
 * between the handoff's own check and this call (API 34), throws rather than returning an error.
 * On that failure this service stops itself and falls through to the same expedited-work
 * enqueuer the handoff layer's own refused-start fallback uses (finding 4).
 *
 * **A39 review, finding 7:** [timeoutJob] is `@Volatile` (written on the main thread from
 * [onStartCommand], read/cancelled from [Dispatchers.Default]) and every `stopSelf` call passes
 * this start's own `startId`, so a second `LOCATE_REQUEST` arriving while the first is still in
 * flight can no longer have its capture killed mid-way by the first's orphaned timeout — Android
 * only honours `stopSelf(startId)` once no more recent start has been delivered.
 *
 * **A39's final round, finding 1 (Major):** this service is a singleton — a second
 * `LOCATE_REQUEST` landing on this branch while the first is still in flight re-delivers via
 * [onStartCommand] on the *same* instance, not a new one. The notification id passed to
 * `startForeground` is now derived per request ([LocateNotifier.notificationIdFor]) instead of a
 * single global constant, so two overlapping requests here show two distinct notifications
 * instead of one overwriting the other. [finish] cancels only its own request's notification id
 * explicitly, and detaches from the foreground state (`STOP_FOREGROUND_DETACH`, which — unlike the
 * previous `STOP_FOREGROUND_REMOVE` — never touches a notification) rather than relying on
 * `stopForeground`'s single "current" notification, which is Android's own OS-level foreground
 * bookkeeping for the *service*, not per request; that call is a no-op for a request that isn't
 * the one Android currently associates with this service's foreground state, whichever that is.
 * A literal double-overlap on this exact branch for the exact same device is therefore no longer
 * able to remove the *other* request's notification — the failure this finding exists to fix —
 * though the service may drop its formal OS foreground designation as soon as the first of the two
 * finishes, a few seconds early for the second; that residual was reported, not fixed, in that
 * round (see the A39 final-round report) and filed as its own task, **A44**.
 *
 * **A44:** fixed with [InFlightLocateRequestTracker] — [finish] now calls
 * `stopForeground(STOP_FOREGROUND_DETACH)` only when [inFlightRequests] reports this was the
 * *last* currently in-flight request's completion, not on every completion. This is additive
 * alongside `stopSelf(startId)` (finding 7 above), not redundant with it: `stopSelf(startId)`
 * already stops Android from killing the *service process* out from under a second in-flight
 * request, but nothing about that semantics touches `stopForeground` — `finish()` called
 * `STOP_FOREGROUND_DETACH` unconditionally, with no dependency on `startId` recency, so the OS
 * foreground *designation* could still drop early even though the process itself correctly
 * stayed alive. Read as a **bounded priority dip fix, not a data-loss or notification-content
 * fix**: A39 already scoped the notification id per `requestId` ([LocateNotifier.notificationIdFor]),
 * so both requests already kept their own notification and both captures already fulfilled either
 * way — this closes the last few seconds where the second request's foreground *designation*
 * could drop while it was still capturing.
 */
class LocateForegroundService : Service() {

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        Log.w(TAG, "LOCATE_REQUEST capture failed (${throwable::class.simpleName})")
    }
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default + exceptionHandler)

    @Volatile
    private var timeoutJob: Job? = null

    /** A44 (specs/009 §5.1): counts requests currently in flight on this singleton service
     * instance so [finish] only detaches the OS foreground designation on the *last* one to
     * complete. See [InFlightLocateRequestTracker]'s own doc for why this is additive alongside
     * `stopSelf(startId)`, not redundant with it. */
    private val inFlightRequests = InFlightLocateRequestTracker()

    private lateinit var notifier: LocateNotifier

    override fun onCreate() {
        super.onCreate()
        notifier = LocateNotifier(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val data = intent.toDataMap()
        val notification = notifier.buildNotification(data)
        val notificationId = notifier.notificationIdFor(data)

        try {
            startForeground(notificationId, notification)
        } catch (e: Exception) {
            // Code-review fix (finding 3): fall through to the expedited-work fallback rather than
            // dropping the request outright - same fallback chain finding 4's handoff-layer guard
            // uses for a refused startForegroundService call.
            stopSelf(startId)
            (application as FindlyApplication).container.locateRequestWorkEnqueuer.enqueue(data)
            return START_NOT_STICKY
        }

        // A44: one token per request, started before either coroutine below can race to
        // complete it - `inFlightRequests.finish(token)` is what decides whether *this*
        // completion is the one that gets to detach the service's foreground designation.
        val requestToken = inFlightRequests.start()

        timeoutJob = serviceScope.launch {
            kotlinx.coroutines.delay(HARD_CAP_MILLIS)
            finish(startId, notificationId, requestToken)
        }

        serviceScope.launch {
            try {
                val container = (application as FindlyApplication).container
                container.locateRequestPushHandler.handle(data)
            } finally {
                finish(startId, notificationId, requestToken)
            }
        }

        return START_NOT_STICKY
    }

    /** Idempotent — the timeout coroutine and the capture coroutine race to call this first;
     * `stopSelf(startId)` on an already-stopping service, or one superseded by a newer start, is a
     * safe no-op (see class doc, finding 7). [notificationId] is this call's own request's id
     * (finding 1, A39's final round): cancelling it explicitly, instead of the previous
     * `stopForeground(STOP_FOREGROUND_REMOVE)`, never removes a *different* still-in-flight
     * request's notification merely because Android currently associates it with this service's
     * foreground state — `STOP_FOREGROUND_DETACH` relinquishes that state without touching any
     * notification's content.
     *
     * **A44:** [requestToken] identifies *this request's* completion to [inFlightRequests] —
     * `stopForeground(STOP_FOREGROUND_DETACH)` now only runs when [InFlightLocateRequestTracker.finish]
     * reports this was the last of all currently in-flight requests, not on every completion,
     * closing the early-detach residual A39's final round reported but deliberately left unfixed.
     * `finish()` being called twice for one request (this method's own "idempotent" framing above)
     * is exactly why the tracker's own per-token guard exists — it must decrement the shared count
     * at most once per request no matter how many times this method runs for it. */
    private fun finish(startId: Int, notificationId: Int, requestToken: InFlightLocateRequestTracker.RequestToken) {
        timeoutJob?.cancel()
        NotificationManagerCompat.from(this).cancel(notificationId)
        if (inFlightRequests.finish(requestToken)) {
            stopForeground(STOP_FOREGROUND_DETACH)
        }
        stopSelf(startId)
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun Intent?.toDataMap(): Map<String, String> {
        val extras = this?.extras ?: return emptyMap()
        return extras.keySet().mapNotNull { key -> extras.getString(key)?.let { key to it } }.toMap()
    }

    companion object {
        private const val TAG = "LocateForegroundService"
        private const val HARD_CAP_MILLIS = 45_000L
    }
}
