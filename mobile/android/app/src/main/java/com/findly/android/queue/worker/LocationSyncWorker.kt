package com.findly.android.queue.worker

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

/**
 * WorkManager glue for the ≥15-minute / once-daily schedule (specs/009-device-runtime.md §3.1/
 * §3.3). All actual sync-cycle logic lives in the tested [LocationSyncRunner]; this class's only
 * job is to invoke it once per WorkManager-triggered run and map [RunResult] onto WorkManager's
 * `Result` (`RunResult.Retry` → `Result.retry()`, which WorkManager backs off per the
 * `setBackoffCriteria` configured in [LocationSyncScheduler] — §9: "exponential, 30s initial").
 * Constructed by [FindlyWorkerFactory] (not WorkManager's default no-arg path) so [runner] can be
 * a real, fully-wired [LocationSyncRunner] from `AppContainer`. [runner] is nullable because
 * WorkManager can in principle replay a scheduled run after sign-out, when there is no
 * signed-in device to build one for — that's a clean no-op, never a crash. Untested
 * Android-framework glue by design — mirrors the backend's untested `src/functions`
 * (backend/README.md's hexagonal split).
 */
class LocationSyncWorker(
    context: Context,
    workerParams: WorkerParameters,
    private val runner: LocationSyncRunner?,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val runner = runner ?: return Result.success()
        return when (runner.runOnce()) {
            RunResult.Success -> Result.success()
            RunResult.Retry -> Result.retry()
        }
    }
}
