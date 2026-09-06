package com.findly.android.queue.worker

import android.content.Intent
import android.os.IBinder
import android.util.Log
import android.app.Service
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
 */
class LocateForegroundService : Service() {

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        Log.w(TAG, "LOCATE_REQUEST capture failed", throwable)
    }
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default + exceptionHandler)

    @Volatile
    private var timeoutJob: Job? = null

    private lateinit var notifier: LocateNotifier

    override fun onCreate() {
        super.onCreate()
        notifier = LocateNotifier(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val data = intent.toDataMap()
        val notification = notifier.buildNotification(data)

        try {
            startForeground(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            // Code-review fix (finding 3): fall through to the expedited-work fallback rather than
            // dropping the request outright - same fallback chain finding 4's handoff-layer guard
            // uses for a refused startForegroundService call.
            stopSelf(startId)
            (application as FindlyApplication).container.locateRequestWorkEnqueuer.enqueue(data)
            return START_NOT_STICKY
        }

        timeoutJob = serviceScope.launch {
            kotlinx.coroutines.delay(HARD_CAP_MILLIS)
            finish(startId)
        }

        serviceScope.launch {
            try {
                val container = (application as FindlyApplication).container
                container.locateRequestPushHandler.handle(data)
            } finally {
                finish(startId)
            }
        }

        return START_NOT_STICKY
    }

    /** Idempotent — the timeout coroutine and the capture coroutine race to call this first;
     * `stopSelf(startId)` on an already-stopping service, or one superseded by a newer start, is a
     * safe no-op (see class doc, finding 7). */
    private fun finish(startId: Int) {
        timeoutJob?.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
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
        private const val NOTIFICATION_ID = LocateNotifier.NOTIFICATION_ID
        private const val HARD_CAP_MILLIS = 45_000L
    }
}
