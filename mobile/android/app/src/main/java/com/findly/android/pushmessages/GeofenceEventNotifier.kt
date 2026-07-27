package com.findly.android.pushmessages

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.findly.android.R

/**
 * Posts the real system notification for [GeofenceEventPushHandler] (specs/009-device-runtime.md
 * §5.3). Thin Android-framework glue — untestable off-device by design (same category as
 * `FindlyMessagingService` itself); all the tested logic lives in
 * [GeofenceEventNotificationTemplate]/[GeofenceEventPushHandler].
 *
 * No notification channel infrastructure existed before this class — `ensureChannel` creates one
 * lazily, idempotently (`createNotificationChannel` is itself a safe no-op if the channel already
 * exists).
 *
 * TODO(A13): swap the `ic_launcher` smallIcon placeholder below for the real monochrome
 * `ic_stat_findly` asset (009 §8 — a colored icon renders as a white blob in the status bar,
 * Android draws status icons as a mask) once A13 copies
 * `design/findly-icon/android/ic_stat_findly.xml` into `res/drawable`
 * (design/findly-icon/README.md assigns that integration to A13, not this task).
 */
class GeofenceEventNotifier(private val context: Context) : GeofenceNotifier {

    override fun notify(title: String) {
        ensureChannel()
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(title.hashCode(), notification)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted (specs/003-android-client.md §11 point 4) - drop
            // silently, same as every other best-effort path in 009 §5.
        }
    }

    private fun ensureChannel() {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Family location alerts", NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
    }

    private companion object {
        const val CHANNEL_ID = "geofence_events"
    }
}
