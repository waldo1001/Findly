package com.findly.android.queue.worker

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import com.findly.android.FindlyApplication
import com.findly.android.MainActivity
import com.findly.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The specs/009-device-runtime.md §3.2 foreground service for 5/10-minute sync intervals —
 * WorkManager's periodic floor is 15 minutes (§3.1), so this self-rescheduling service is the
 * only way to honor a tighter cadence. Started/stopped **exclusively** through
 * [ForegroundServiceController] ([LocationSyncScheduler] is the only real caller) — never call
 * `startService`/`stopService` on this class directly from elsewhere. All sync-cycle logic is the
 * same tested [LocationSyncRunner] the WorkManager path uses (via `AppContainer`); this class only
 * owns the tick timing, the manual (non-WorkManager) [BackoffPolicy] application on a transient
 * failure (via [ServiceTickPolicy]), and the persistent notification. Thin, untested
 * Android-framework glue by design.
 *
 * Notification copy is 009 §3.2's exact normative text — MUST NOT be silenced or disguised (Play
 * policy for background location).
 *
 * **A40 — Doze-safe tick (specs/009 §3.2):** the cadence is driven by
 * `AlarmManager.setAndAllowWhileIdle` re-entering this service on its own [ACTION_TICK]
 * `PendingIntent`, never a coroutine `delay` (which Doze defers to a maintenance window while the
 * phone is still). One `runOnce` cycle runs per `onStartCommand` call, then the next alarm is
 * scheduled from [ServiceTickPolicy]'s result. Deliberately **not**
 * `setExactAndAllowWhileIdle` — that needs `SCHEDULE_EXACT_ALARM`, which this app must not
 * request (specs/009 §3.2 task brief).
 *
 * **A40 — null-intent restart (specs/009 §3.2 "Restart and recovery"):** `START_STICKY` means the
 * OS may restart this service with a **null** `Intent` after killing it. That case (and any other
 * intent that carries neither [ACTION_TICK] nor a fresh `EXTRA_SYNC_INTERVAL_MINUTES`) is routed
 * through [ServiceRestartDecision], which reads the cached settings
 * (`AppContainer.deviceSettingsStateStore`, the same store §3.5 writes) and either resumes the
 * cycle at the cached interval or `stopSelf()`s — never sits foregrounded with no loop running.
 */
class LocationForegroundService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var cycleJob: Job? = null

    /** Guards against re-triggering an immediate `runOnce` on a redundant `startForegroundService`
     * call while a cycle is already scheduled (§3.2: "a redundant `startForegroundService`...
     * [is] a no-op when nothing changed") — the service's own lifetime is the only state that
     * matters here; a real cadence is driven by the [ACTION_TICK] alarm, not this flag.
     *
     * Code-review fix (finding 6, post-A40 review): `@Volatile` — written from `onStartCommand`
     * (main thread) and read from the [Dispatchers.Default] `runCycle`/tick-scheduling coroutine;
     * without it a write on one thread was not guaranteed visible to a read on the other. */
    @Volatile
    private var cycleStarted = false

    /** The `syncIntervalMinutes` the currently-running (or most recently started) cycle is using —
     * `null` before the first [runCycle] call. Code-review fix (finding 4, post-A40 review): used
     * by [ForegroundCycleRestartDecision] to detect a changed interval arriving while [cycleStarted]
     * is already `true`, so a mid-cycle change (e.g. 5 -> 10) is rebuilt immediately per specs/009
     * §3.5, rather than silently kept at the stale cadence. Same threading rationale as
     * [cycleStarted] above. */
    @Volatile
    private var currentSyncIntervalMinutes: Int? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())

        if (intent?.action == ACTION_TICK) {
            val interval = intent.getIntExtra(EXTRA_SYNC_INTERVAL_MINUTES, -1)
            val attempt = intent.getIntExtra(EXTRA_ATTEMPT, 1)
            if (interval > 0) runCycle(interval, attempt) else stopSelf()
            return START_STICKY
        }

        val extraInterval = intent?.getIntExtra(EXTRA_SYNC_INTERVAL_MINUTES, -1)?.takeIf { it > 0 }
        if (extraInterval != null) {
            // Code-review fix (finding 4, post-A40 review, specs/009 §3.5): a same-interval start
            // while a cycle is already running stays a no-op, but a *different* interval (e.g.
            // 5 -> 10) MUST cancel the stale pending tick and rebuild the cycle immediately rather
            // than keep ticking at the interval baked into the already-scheduled alarm.
            when (ForegroundCycleRestartDecision.decide(cycleStarted, currentSyncIntervalMinutes, extraInterval)) {
                ForegroundCycleRestartDecision.Action.StartFreshCycle -> {
                    cancelPendingTick()
                    runCycle(extraInterval, attempt = 1)
                }
                ForegroundCycleRestartDecision.Action.Ignore -> Unit
            }
        } else if (!cycleStarted) {
            // A null/absent Intent means either a fresh START_STICKY OS restart or some other
            // unrecognised start - specs/009 §3.2 "Restart and recovery": read the cached
            // interval and resume, or stop rather than sit foregrounded with no loop.
            cycleStarted = true
            serviceScope.launch {
                val container = (application as FindlyApplication).container
                when (val decision = ServiceRestartDecision.decide(container.cachedDeviceSettings())) {
                    is ServiceRestartDecision.StartWithInterval -> runCycle(decision.syncIntervalMinutes, attempt = 1)
                    ServiceRestartDecision.Stop -> stopSelf()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        cycleJob?.cancel()
        serviceScope.cancel()
        cancelPendingTick()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun runCycle(syncIntervalMinutes: Int, attempt: Int) {
        // Code-review fix (finding 6, post-A40 review): cancel any still-running cycle before
        // replacing cycleJob - without this, an ACTION_TICK arriving mid-cycle (or the finding-4
        // fresh-cycle path above) could leave two concurrent runOnce()s in flight.
        cycleJob?.cancel()
        cycleStarted = true
        currentSyncIntervalMinutes = syncIntervalMinutes
        cycleJob = serviceScope.launch {
            val runner = (application as FindlyApplication).container.locationSyncRunnerOrNull()
            if (runner == null) {
                stopSelf()
                return@launch
            }
            // Code-review fix (finding 2, post-A40 review): a throwing runOnce() used to skip
            // scheduleNextTick entirely, leaving the service foregrounded forever with the
            // persistent notification and no future alarm - exactly the "never sit foregrounded
            // with no loop" state 009 §3.2 forbids, recoverable only by a process restart. The
            // finally guarantees a next tick is always scheduled; on failure it takes the same
            // backing-off retry path a transient RunResult.Retry would. `isActive` is false when
            // this job was itself the one cancelled by the guard above (a fresh cycle superseding
            // it) - skip scheduling in that case so a fresh, non-cancelled job's own schedule call
            // isn't raced/overwritten by this stale one's.
            var result: RunResult = RunResult.Retry
            try {
                result = runner.runOnce()
            } catch (e: Exception) {
                result = RunResult.Retry
            } finally {
                if (isActive) {
                    val nextTick = ServiceTickPolicy.next(result, attempt, syncIntervalMinutes)
                    scheduleNextTick(syncIntervalMinutes, nextTick.nextAttempt, nextTick.delayMillis)
                }
            }
        }
    }

    private fun scheduleNextTick(syncIntervalMinutes: Int, attempt: Int, delayMillis: Long) {
        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + delayMillis,
            tickPendingIntent(syncIntervalMinutes, attempt),
        )
    }

    /** Code-review fix (finding 5, post-A40 review): `FLAG_UPDATE_CURRENT` (the previous flag
     * here) creates a `PendingIntent` when none exists and overwrites the live one's extras with
     * zeroes before cancelling it - harmless in practice (cancellation still worked) but wrong.
     * `FLAG_NO_CREATE` only looks up an existing registration, so a no-op stays a true no-op. The
     * scheduling path's own `FLAG_IMMUTABLE` in [tickPendingIntent] is unchanged. */
    private fun cancelPendingTick() {
        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        val tickIntent = Intent(this, LocationForegroundService::class.java).setAction(ACTION_TICK)
        val pendingIntent = PendingIntent.getService(
            this,
            TICK_REQUEST_CODE,
            tickIntent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarmManager.cancel(pendingIntent)
    }

    /** `FLAG_UPDATE_CURRENT` refreshes this same request code's extras on every call, so the one
     * `AlarmManager` registration always carries the interval/attempt for the *next* tick. */
    private fun tickPendingIntent(syncIntervalMinutes: Int, attempt: Int): PendingIntent {
        val tickIntent = Intent(this, LocationForegroundService::class.java)
            .setAction(ACTION_TICK)
            .putExtra(EXTRA_SYNC_INTERVAL_MINUTES, syncIntervalMinutes)
            .putExtra(EXTRA_ATTEMPT, attempt)
        return PendingIntent.getService(
            this,
            TICK_REQUEST_CODE,
            tickIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildNotification(): Notification {
        // 009 §3.2: "a tap action opening the app's device-settings screen" - MainActivity reads
        // this extra (gated to a fresh launch, same idiom as the https-join-link intent handling,
        // MainActivity.kt's doc) and navigates FindlyNavHost to Destinations.Devices once
        // (specs/010-app-shell-and-screen-ux.md sec4.1 -- the retired Settings monolith's
        // replacement).
        val settingsIntent = Intent(this, MainActivity::class.java)
            .putExtra(EXTRA_OPEN_DEVICES, true)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            settingsIntent,
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

        /** Read by [com.findly.android.MainActivity] off its launching `Intent` (009 §3.2's
         * notification tap target). */
        const val EXTRA_OPEN_DEVICES = "openDevices"

        /** A40: this service's own re-entry action for the Doze-safe `AlarmManager` tick — never
         * sent by anything but [scheduleNextTick]/[tickPendingIntent] above. */
        private const val ACTION_TICK = "com.findly.android.action.LOCATION_FOREGROUND_SERVICE_TICK"
        private const val EXTRA_ATTEMPT = "attempt"
        private const val TICK_REQUEST_CODE = 1002
        private const val CHANNEL_ID = "findly_location_sharing"
        private const val CHANNEL_NAME = "Location sharing"
        private const val NOTIFICATION_ID = 1001
    }
}
