package com.findly.android.pushmessages

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.findly.android.R

/**
 * specs/009-device-runtime.md §5.1 (amended 2026-09-06 — A39's review, finding 1): the single
 * notifier shared by all three `LOCATE_REQUEST` handoff branches —
 * [com.findly.android.queue.worker.LocateForegroundService],
 * [com.findly.android.queue.worker.LocateRequestWorker]'s expedited-work foreground info, and the
 * §5.1-option-3 "presence service already running" direct-capture branch wired in `AppContainer` —
 * so every branch posts the `findly_locate` notification, not just the foreground-service one. On
 * Android the `LOCATE_REQUEST` FCM message is data-only by design (001 §8.1), so the client is the
 * only thing that ever renders the "X is locating you" title; a branch that captures without
 * posting produces a silent locate — the exact failure this amendment removes — and, because FCM
 * demotes apps whose high-priority messages produce no notification, a silent branch actively
 * degrades delivery for every future locate too.
 *
 * Callers MUST call [post] before the capture and [cancel] in a `finally` around it. The
 * foreground-service branch instead passes [buildNotification]'s result straight to
 * `startForeground`, and the expedited-work branch passes it to `getForegroundInfo()` — both of
 * those already "post" via the OS's own foreground-service machinery, so they must not also call
 * [post].
 *
 * **Per-request notification id (amended 2026-09-06, A39's final round, finding 1 — Major):** the
 * id is no longer a single global constant. [notificationIdFor] derives it from `requestId` (see
 * [LocateNotificationId]) so two requests in flight at once — landing in different branches, or
 * even the same branch twice — never share a slot; finishing one request's capture can then never
 * remove a different request's still-active notification. [post] and [cancel] take the raw push
 * `data` map and derive the id themselves so every caller of a given request agrees on it; the
 * `startForeground`/`getForegroundInfo` callers derive it the same way via [notificationIdFor].
 *
 * Thin, untested Android-framework glue by design (same bucket as [GeofenceEventNotifier]) — the
 * *decidable* part of what it does ([LocateNotificationTitle] and [LocateNotificationId]) is pure,
 * tested Kotlin.
 */
class LocateNotifier(private val context: Context) {

    fun buildNotification(data: Map<String, String>): Notification {
        ensureChannel()
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(LocateNotificationTitle.forRequesterData(data))
            .setSmallIcon(R.drawable.ic_stat_findly)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
    }

    /** The per-request notification id for this push `data` map — see [LocateNotificationId] and
     * the class doc's "Per-request notification id" note (finding 1). Used directly by
     * [com.findly.android.queue.worker.LocateForegroundService]'s `startForeground` and
     * [com.findly.android.queue.worker.LocateRequestWorker.getForegroundInfo], and internally by
     * [post]/[cancel]. */
    fun notificationIdFor(data: Map<String, String>): Int =
        LocateNotificationId.forRequestId(data["requestId"].orEmpty())

    /** Used by the presence-reuse direct-capture branch only — the other two branches post via
     * their own OS-level foreground-service API instead (see class doc). */
    fun post(data: Map<String, String>, notification: Notification) {
        try {
            NotificationManagerCompat.from(context).notify(notificationIdFor(data), notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted (specs/003-android-client.md §11 point 4) - drop
            // silently, same as every other best-effort notification path in 009 §5.
        }
    }

    fun cancel(data: Map<String, String>) {
        NotificationManagerCompat.from(context).cancel(notificationIdFor(data))
    }

    private fun ensureChannel() {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }

    companion object {
        /** specs/009 §5.1: "the locate notification channel is `findly_locate` (importance
         * DEFAULT...)". */
        const val CHANNEL_ID = "findly_locate"
        private const val CHANNEL_NAME = "Locate requests"
    }
}
