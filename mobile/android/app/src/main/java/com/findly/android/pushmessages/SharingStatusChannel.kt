package com.findly.android.pushmessages

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

/**
 * The `findly_sharing_status` notification channel (specs/011 §4.4, 009 §5.6, 001 §8.8): the
 * `STALE_NUDGE` push names it as `android.notification.channel_id`, so it MUST exist before the
 * first nudge arrives — an FCM `notification` addressed to a missing channel falls back to a
 * generic one the user cannot tell apart. Created at application start; creation is idempotent.
 */
object SharingStatusChannel {
    const val ID = "findly_sharing_status"
    const val NAME = "Sharing reminders"

    /** `NotificationManager.IMPORTANCE_DEFAULT`. */
    const val IMPORTANCE = NotificationManager.IMPORTANCE_DEFAULT

    fun ensureCreated(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(ID) == null) {
            manager.createNotificationChannel(NotificationChannel(ID, NAME, IMPORTANCE))
        }
    }
}
