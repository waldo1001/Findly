package com.findly.android.queue.worker

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.findly.android.location.settings.SettingsPoller

/**
 * The low-frequency (§4: "at least every 6 hours") background half of the pull-based resume poll
 * (specs/009-device-runtime.md §4) — the other half is the app-foreground trigger
 * (`AppContainer.onAppForeground`), both calling the exact same [SettingsPoller.poll]. Runs
 * unconditionally on its schedule regardless of current pause state (harmless/no-op when not
 * paused — [com.findly.android.location.settings.DeviceSettingsCoordinator.applySettings] only
 * acts on an actual change). Untested Android-framework glue by design.
 */
class SettingsPollWorker(
    context: Context,
    workerParams: WorkerParameters,
    private val settingsPoller: SettingsPoller?,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        settingsPoller?.poll()
        // Always a clean success: a poll failure (network, DEVICE_NOT_FOUND, ...) is not this
        // worker's concern to retry aggressively - the next scheduled run (or the next app
        // foreground) tries again; §4 asks for "at least every 6 hours", not guaranteed delivery.
        return Result.success()
    }
}
