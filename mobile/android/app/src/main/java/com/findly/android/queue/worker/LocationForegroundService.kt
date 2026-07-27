package com.findly.android.queue.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.findly.android.FindlyApplication
import com.findly.android.MainActivity
import com.findly.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The specs/009-device-runtime.md §3.2 foreground service for 5/10-minute sync intervals —
 * WorkManager's periodic floor is 15 minutes (§3.1), so this self-rescheduling-timer service is
 * the only way to honor a tighter cadence. Started/stopped **exclusively** through
 * [ForegroundServiceController] ([LocationSyncScheduler] is the only real caller) — never call
 * `startService`/`stopService` on this class directly from elsewhere. All sync-cycle logic is the
 * same tested [LocationSyncRunner] the WorkManager path uses (via `AppContainer`); this class only
 * owns the loop timing, the manual (non-WorkManager) [BackoffPolicy] application on a transient
 * failure, and the persistent notification. Thin, untested Android-framework glue by design.
 *
 * Notification copy is 009 §3.2's exact normative text — MUST NOT be silenced or disguised (Play
 * policy for background location).
 */
class LocationForegroundService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var loopJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())

        val syncIntervalMinutes = intent?.getIntExtra(EXTRA_SYNC_INTERVAL_MINUTES, -1)?.takeIf { it > 0 }
        if (syncIntervalMinutes != null && loopJob == null) {
            val runner = (application as FindlyApplication).container.locationSyncRunnerOrNull()
            if (runner != null) {
                loopJob = serviceScope.launch { runLoop(syncIntervalMinutes, runner) }
            } else {
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        loopJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private suspend fun runLoop(syncIntervalMinutes: Int, runner: LocationSyncRunner) {
        var attempt = 1
        while (true) {
            when (runner.runOnce()) {
                RunResult.Success -> {
                    attempt = 1
                    delay(syncIntervalMinutes * MILLIS_PER_MINUTE)
                }
                // specs/009 §9: exponential backoff, capped at the sync interval - never back off
                // past the next natural capture. WorkManager's own Result.retry() mechanism
                // doesn't apply here (this loop isn't WorkManager-driven), hence BackoffPolicy.
                RunResult.Retry -> {
                    val delayMillis = BackoffPolicy.delayMillisForAttempt(attempt, syncIntervalMinutes)
                    attempt++
                    delay(delayMillis)
                }
            }
        }
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.foreground_sync_notification_title))
            .setContentText(getString(R.string.foreground_sync_notification_body))
            .setSmallIcon(R.drawable.ic_stat_locating)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val EXTRA_SYNC_INTERVAL_MINUTES = "syncIntervalMinutes"
        private const val CHANNEL_ID = "findly_location_sharing"
        private const val CHANNEL_NAME = "Location sharing"
        private const val NOTIFICATION_ID = 1001
        private const val MILLIS_PER_MINUTE = 60_000L
    }
}
