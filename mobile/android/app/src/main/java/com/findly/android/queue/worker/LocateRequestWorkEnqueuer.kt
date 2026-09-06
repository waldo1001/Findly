package com.findly.android.queue.worker

import android.content.Context
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager

/**
 * specs/009-device-runtime.md §5.1's expedited `WorkManager` fallback path — enqueues
 * [LocateRequestWorker] with `setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)` so
 * it runs as soon as the quota allows, degrading gracefully to ordinary work rather than failing
 * outright when the app's expedited-work quota is exhausted. (The A39 task brief named this
 * constant `RUN_AS_NON_EXPEDITED_WORK_REQUEST_FALLBACK`; verified against the actual
 * androidx.work:2.10.0 bytecode — no such constant exists, only `RUN_AS_NON_EXPEDITED_WORK_REQUEST`
 * and `DROP_WORK_REQUEST` — used here since it's unambiguously the one the brief meant.) Not a
 * *unique* work request — concurrent `LOCATE_REQUEST`s (rare, but not impossible) each get their
 * own run rather than clobbering one another. Thin, untested Android-framework glue by design
 * (same bucket as [DefaultForegroundServiceController]).
 */
class LocateRequestWorkEnqueuer(private val context: Context) {
    fun enqueue(data: Map<String, String>) {
        val inputData = Data.Builder().apply {
            data.forEach { (key, value) -> putString(key, value) }
        }.build()
        val request = OneTimeWorkRequestBuilder<LocateRequestWorker>()
            .setInputData(inputData)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        WorkManager.getInstance(context).enqueue(request)
    }
}
