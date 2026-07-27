package com.findly.android.queue.worker

/**
 * Starts/stops the specs/009-device-runtime.md §3.2 foreground service (5/10-minute intervals).
 * [DefaultForegroundServiceController] is the real, `Context`/`Service`-touching implementation —
 * this interface is what keeps [SyncStrategySelector]'s caller (`DefaultSyncScheduler`)
 * swappable/testable. Both methods MUST be idempotent (start-while-started, stop-while-stopped
 * are both routine — e.g. pause calling `stop()` when the service was never running).
 */
interface ForegroundServiceController {
    fun start(syncIntervalMinutes: Int)
    fun stop()
}
