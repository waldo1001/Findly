package com.findly.android.queue.worker

/**
 * Whether [LocationForegroundService] (specs/009-device-runtime.md §3.2) is currently alive **and
 * actually running a sync cycle** in this process — a plain, process-wide flag rather than a
 * binder/query round-trip, since the only consumer
 * ([com.findly.android.pushmessages.LocateRequestHandoff], via `AppContainer`, specs/009 §5.1
 * option 3: "if the presence service is already running, it MAY perform the capture directly...
 * no second service") needs a fast, synchronous read.
 *
 * Code-review fix (finding 8, A39 review): previously set `true` in
 * [LocationForegroundService.onCreate], before the null-intent [ServiceRestartDecision] branch
 * could still decide to `stopSelf()` — in that window a locate would have routed to this branch
 * with no foreground service actually alive, a background high-accuracy capture the platform
 * throttles hard. Now set only in [LocationForegroundService]'s `runCycle` — the point where the
 * service actually commits to running a cycle, always reached after `onStartCommand`'s own
 * `startForeground()` call — and cleared both in `onDestroy` and explicitly in the
 * [ServiceRestartDecision.Stop] branch before its own `stopSelf()`. (The flag is process-local, so
 * a kill that skips `onDestroy` destroys it too — no OOM-survival concern here.) `@Volatile` for
 * the same cross-thread-visibility reason as that class's own flags (see its doc).
 */
object PresenceServiceState {
    @Volatile
    var isRunning: Boolean = false
}
