package com.findly.android.queue.worker

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Real, `Context`-backed [ForegroundServiceController] (specs/009-device-runtime.md §3.2) —
 * starts/stops [LocationForegroundService] via `Intent`s. Thin Android-framework glue, untested
 * (same bucket as `AndroidDeviceInfoProvider`, specs/003-android-client.md §3); both methods are
 * idempotent by construction (Android itself no-ops a redundant `startForegroundService`/
 * `stopService` call).
 */
class DefaultForegroundServiceController(private val context: Context) : ForegroundServiceController {

    override fun start(syncIntervalMinutes: Int) {
        val intent = Intent(context, LocationForegroundService::class.java)
            .putExtra(LocationForegroundService.EXTRA_SYNC_INTERVAL_MINUTES, syncIntervalMinutes)
        ContextCompat.startForegroundService(context, intent)
    }

    override fun stop() {
        context.stopService(Intent(context, LocationForegroundService::class.java))
    }
}
