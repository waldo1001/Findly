package com.findly.android.queue.worker

import android.content.Context
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager

/**
 * A43 (specs/009-device-runtime.md §5.4/§6.2): enqueues [GeofenceConfigSyncWorker] expedited -
 * `setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)`, same policy and rationale as
 * [LocateRequestWorkEnqueuer] (degrades gracefully to ordinary work rather than failing outright
 * when the app's expedited-work quota is exhausted) - so `FindlyMessagingService` can hand off a
 * `GEOFENCE_CONFIG_CHANGED` push and return immediately instead of `runBlocking` through the real
 * `GET /geofences` + `GeofencingClient` re-registration cycle inside its ~10s callback budget.
 *
 * No input `Data` - unlike [LocateRequestWorkEnqueuer], [GeofenceConfigSyncWorker] needs nothing
 * from the push payload; [com.findly.android.pushmessages.GeofenceConfigChangedPushHandler.handle]
 * takes no arguments. Not a unique work request, for the same reason as
 * [LocateRequestWorkEnqueuer]: a second `GEOFENCE_CONFIG_CHANGED` arriving while one sync is still
 * in flight just runs its own redundant-but-harmless full re-sync rather than being dropped.
 *
 * Thin, untested Android-framework glue by design (same bucket as [LocateRequestWorkEnqueuer]).
 */
class GeofenceConfigSyncWorkEnqueuer(private val context: Context) {
    fun enqueue() {
        val request = OneTimeWorkRequestBuilder<GeofenceConfigSyncWorker>()
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        WorkManager.getInstance(context).enqueue(request)
    }
}
