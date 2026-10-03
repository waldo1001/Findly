package com.findly.android.queue.worker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.findly.android.R
import com.findly.android.pushmessages.GeofenceConfigChangedPushHandler

/**
 * A43 (specs/009-device-runtime.md §5.4/§6.2): the same expedited-`WorkManager` seam A39 built for
 * the demoted-`LOCATE_REQUEST` fallback ([LocateRequestWorker]), reused here so
 * `FindlyMessagingService.onMessageReceived` can return immediately for `GEOFENCE_CONFIG_CHANGED`
 * too. [GeofenceConfigChangedPushHandler.handle] performs a real `GET /geofences` plus a full
 * `GeofencingClient` unregister/re-register cycle with no timeout tied to the callback's ~10s
 * budget - on a slow connection that could approach or exceed it, risking the process losing its
 * Doze exemption mid-re-registration (009 §6.2's documented "zero geofences registered" state).
 * Running it here instead removes that risk; it does not change what §6.2 already tolerates as
 * the eventual self-healing bound (the next report's `geofenceEtag` piggyback) - this is a
 * robustness fix, not a data-loss fix.
 *
 * On API <= 30, `WorkManager` runs expedited work as a foreground service and calls
 * [getForegroundInfo] before [doWork] - the default `CoroutineWorker` implementation throws, so
 * without this override the branch never runs on Android 8-11 (same finding A39 made for
 * [LocateRequestWorker]). From API 31 it runs as an expedited job and never calls it.
 *
 * **Typeless, unlike [LocateRequestWorker] (A50, specs/003-android-client.md §11.6).** This work is
 * a network fetch plus geofence-registration bookkeeping, never a GPS capture, so the location
 * type would be wrong. A43 used `FOREGROUND_SERVICE_TYPE_DATA_SYNC`, which needs the
 * `FOREGROUND_SERVICE_DATA_SYNC` permission, which needs a Play Console declaration the console
 * could not offer - every publish failed on it (handoff H13/H15). It bought nothing: the only
 * versions that reach this method (below API 31) accept a type of `0`, and the type permissions
 * are enforced only from API 34. Do not reintroduce a type here without that declaration existing
 * first; `ForegroundServiceTypeDeclarationTest` fails if the manifest side comes back.
 *
 * Untested Android-framework glue by design (same bucket as [LocateRequestWorker]/
 * [SettingsPollWorker]).
 */
class GeofenceConfigSyncWorker(
    context: Context,
    workerParams: WorkerParameters,
    private val geofenceConfigChangedPushHandler: GeofenceConfigChangedPushHandler?,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        geofenceConfigChangedPushHandler?.handle()
        // Always a clean success: GeofenceConfigSyncCoordinator.sync() is itself a silent
        // best-effort no-op on a fetch failure (its own doc) - nothing here for WorkManager's own
        // retry policy to act on, same rationale as LocateRequestWorker/SettingsPollWorker.
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        ensureChannel()
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(applicationContext.getString(R.string.geofence_sync_notification_title))
            .setSmallIcon(R.drawable.ic_stat_findly)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
        return ForegroundInfo(NOTIFICATION_ID, notification)
    }

    private fun ensureChannel() {
        val manager = applicationContext.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_MIN),
            )
        }
    }

    private companion object {
        const val CHANNEL_ID = "findly_background_sync"
        const val CHANNEL_NAME = "Background sync"

        // LocationForegroundService's presence notification is 1001; LocateNotificationId derives
        // ids from [2001, 2001 + 999_983). This fixed id sits below both - GEOFENCE_CONFIG_CHANGED
        // sync is never in flight more than once meaningfully (WorkManager just runs the latest
        // full re-sync), so one shared slot is correct, not a bug the way it would be for Locate.
        const val NOTIFICATION_ID = 1501
    }
}
