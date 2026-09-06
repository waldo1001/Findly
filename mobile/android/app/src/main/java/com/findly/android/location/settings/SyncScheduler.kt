package com.findly.android.location.settings

/**
 * The scheduling seam (specs/009-device-runtime.md §3) — [reschedule] picks WorkManager vs. the
 * foreground service per [com.findly.android.queue.worker.EffectiveSyncStrategySelector] and
 * (re)builds whichever one applies; [cancelAll] tears down both unconditionally (pause, sign-out).
 * `LocationSyncScheduler` (queue/worker/) is the real, `Context`/`WorkManager`-touching
 * implementation; this interface is what keeps [DeviceSettingsCoordinator] itself pure/testable.
 *
 * [reschedule] is `suspend` (A41, specs/009 §3.2) because choosing the *effective* strategy needs
 * a fresh `ACCESS_BACKGROUND_LOCATION` read (`LocationPermissionState.isGranted()`, itself
 * `suspend` since it re-checks system state every call, §7's "never cached, always re-checked").
 * Both real callers — [DeviceSettingsCoordinator.applySettings] and
 * `AppContainer.reapplyCachedScheduleSuspending` — already run inside a coroutine.
 */
interface SyncScheduler {
    suspend fun reschedule(syncIntervalMinutes: Int)
    fun cancelAll()
}
