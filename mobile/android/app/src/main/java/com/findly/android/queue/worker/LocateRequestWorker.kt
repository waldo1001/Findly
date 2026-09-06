package com.findly.android.queue.worker

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.findly.android.pushmessages.LocateRequestPushHandler

/**
 * specs/009-device-runtime.md §5.1's expedited-`WorkManager` fallback: a demoted-priority
 * `LOCATE_REQUEST`, or one with `ACCESS_BACKGROUND_LOCATION` absent, runs the same tested
 * [LocateRequestPushHandler] here instead of the short-lived foreground service
 * ([LocateForegroundService]). Best-effort and possibly late — B26's 10-minute fulfil grace
 * tolerates it. Untested Android-framework glue by design (same bucket as [SettingsPollWorker]).
 */
class LocateRequestWorker(
    context: Context,
    workerParams: WorkerParameters,
    private val locateRequestPushHandler: LocateRequestPushHandler?,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val data = inputData.keyValueMap.mapNotNull { (key, value) ->
            (value as? String)?.let { key to it }
        }.toMap()
        locateRequestPushHandler?.handle(data)
        // Always a clean success, same rationale as SettingsPollWorker: the handler itself is
        // silent on every failure path per 009 §5.1 ("failure to obtain a fix... give up
        // silently"), so there is nothing for WorkManager's own retry policy to act on here.
        return Result.success()
    }
}
