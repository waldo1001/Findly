package com.findly.android.queue.worker

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.findly.android.queue.LocationSyncCoordinator

/**
 * Periodic upload worker **scaffold** (specs/003-android-client.md §10.5). All actual
 * sync-decision logic lives in the tested [LocationSyncCoordinator] — this class's only job,
 * once wired, is to invoke it on WorkManager's schedule.
 *
 * TODO(A2/H1): construct a real [LocationSyncCoordinator] (needs the signed-in user's live
 * `deviceId` + `LocationsApi` from `AppContainer`) and call `syncOnce()` in a loop until
 * `SyncOutcome.NothingToSync`/`Paused`/`TransientFailure`. Not wired or enqueued anywhere yet
 * (see [LocationSyncScheduler]). Untested Android-framework glue by design — mirrors the
 * backend's untested `src/functions` (backend/README.md's hexagonal split).
 */
class LocationSyncWorker(
    context: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        // TODO(A2/H1): wire a real LocationSyncCoordinator and drain the queue here.
        return Result.success()
    }
}
