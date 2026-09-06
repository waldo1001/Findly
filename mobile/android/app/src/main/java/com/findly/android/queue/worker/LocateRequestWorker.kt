package com.findly.android.queue.worker

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.findly.android.pushmessages.LocateNotifier
import com.findly.android.pushmessages.LocateRequestPushHandler

/**
 * specs/009-device-runtime.md §5.1's expedited-`WorkManager` fallback: a demoted-priority
 * `LOCATE_REQUEST`, or one with `ACCESS_BACKGROUND_LOCATION` absent, runs the same tested
 * [LocateRequestPushHandler] here instead of the short-lived foreground service
 * ([LocateForegroundService]). Best-effort and possibly late — B26's 10-minute fulfil grace
 * tolerates it. Untested Android-framework glue by design (same bucket as [SettingsPollWorker]).
 *
 * **A39 review, finding 5:** on API ≤ 30 WorkManager runs expedited work as a foreground service
 * and calls [getForegroundInfo] before [doWork] — the default `CoroutineWorker` implementation
 * throws, so without this override the branch taken for a demoted message or a device lacking
 * background permission never captured at all on Android 8-11. Builds its notification via the
 * same shared [LocateNotifier] the other two handoff branches use (finding 1), so this branch also
 * renders the "X is locating you" title instead of posting nothing.
 *
 * **A39's final round, finding 1 (Major):** the foreground notification id is derived per request
 * via [LocateNotifier.notificationIdFor] rather than a single global constant — each `WorkRequest`
 * gets its own `CoroutineWorker` instance, so this branch never shared a slot with a sibling
 * anyway, but the id must still match what [LocateNotifier.post]/`cancel` and the foreground
 * service derive for the same `requestId`.
 */
class LocateRequestWorker(
    context: Context,
    workerParams: WorkerParameters,
    private val locateRequestPushHandler: LocateRequestPushHandler?,
) : CoroutineWorker(context, workerParams) {

    private val notifier = LocateNotifier(context)

    override suspend fun doWork(): Result {
        locateRequestPushHandler?.handle(inputData.toStringMap())
        // Always a clean success, same rationale as SettingsPollWorker: the handler itself is
        // silent on every failure path per 009 §5.1 ("failure to obtain a fix... give up
        // silently"), so there is nothing for WorkManager's own retry policy to act on here.
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val data = inputData.toStringMap()
        val notification = notifier.buildNotification(data)
        val notificationId = notifier.notificationIdFor(data)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        } else {
            ForegroundInfo(notificationId, notification)
        }
    }

    private fun Data.toStringMap(): Map<String, String> =
        keyValueMap.mapNotNull { (key, value) -> (value as? String)?.let { key to it } }.toMap()
}
