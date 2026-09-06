package com.findly.android.queue.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.findly.android.FindlyApplication
import com.findly.android.R
import com.findly.android.pushmessages.LocateNotificationTitle
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
 * `findly_locate` notification itself (the FCM message is data-only on Android by design, §5.1)
 * and reuses that same notification as its own foreground notification — a single object
 * satisfies both the OS requirement and the user-visible design goal. All the actual capture/
 * fulfil logic is the same tested [com.findly.android.pushmessages.LocateRequestPushHandler] the
 * presence-reuse and WorkManager paths also call — nothing about the capture is duplicated here.
 * Thin, untested Android-framework glue by design (same bucket as [LocationForegroundService]).
 *
 * Hard cap: 45 s (§5.1), then `stopSelf()` regardless of whether the capture finished — never
 * `START_STICKY` (a one-shot service must not be resurrected by the OS after being killed).
 */
class LocateForegroundService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var timeoutJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val data = intent.toDataMap()
        val requestedByName = data["requestedByName"].orEmpty()
        startForeground(NOTIFICATION_ID, buildNotification(requestedByName))

        timeoutJob = serviceScope.launch {
            kotlinx.coroutines.delay(HARD_CAP_MILLIS)
            finish()
        }

        serviceScope.launch {
            try {
                val container = (application as FindlyApplication).container
                container.locateRequestPushHandler.handle(data)
            } finally {
                finish()
            }
        }

        return START_NOT_STICKY
    }

    /** Idempotent — the timeout coroutine and the capture coroutine race to call this first;
     * `stopSelf()` on an already-stopping service is a safe no-op. */
    private fun finish() {
        timeoutJob?.cancel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(requestedByName: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(LocateNotificationTitle.forRequester(requestedByName))
            .setSmallIcon(R.drawable.ic_stat_findly)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT)
        manager.createNotificationChannel(channel)
    }

    private fun Intent?.toDataMap(): Map<String, String> {
        val extras = this?.extras ?: return emptyMap()
        return extras.keySet().mapNotNull { key -> extras.getString(key)?.let { key to it } }.toMap()
    }

    companion object {
        /** specs/009 §5.1: "the locate notification channel is `findly_locate` (importance
         * DEFAULT...)". */
        private const val CHANNEL_ID = "findly_locate"
        private const val CHANNEL_NAME = "Locate requests"
        private const val NOTIFICATION_ID = 2001
        private const val HARD_CAP_MILLIS = 45_000L
    }
}
