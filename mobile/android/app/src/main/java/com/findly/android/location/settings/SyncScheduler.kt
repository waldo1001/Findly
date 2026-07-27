package com.findly.android.location.settings

/**
 * The scheduling seam (specs/009-device-runtime.md §3) — [reschedule] picks WorkManager vs. the
 * foreground service per [com.findly.android.queue.worker.SyncStrategySelector] and (re)builds
 * whichever one applies; [cancelAll] tears down both unconditionally (pause, sign-out).
 * `DefaultSyncScheduler` (queue/worker/) is the real, `Context`/`WorkManager`-touching
 * implementation; this interface is what keeps [DeviceSettingsCoordinator] itself pure/testable.
 */
interface SyncScheduler {
    fun reschedule(syncIntervalMinutes: Int)
    fun cancelAll()
}
