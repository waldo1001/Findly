package com.findly.android.queue.worker

/**
 * Whether [LocationForegroundService] (specs/009-device-runtime.md §3.2) is currently alive in
 * this process — a plain, process-wide flag rather than a binder/query round-trip, since the only
 * consumer ([com.findly.android.pushmessages.LocateRequestHandoff], via `AppContainer`, specs/009
 * §5.1 option 3: "if the presence service is already running, it MAY perform the capture
 * directly... no second service") needs a fast, synchronous read. Set by
 * [LocationForegroundService.onCreate]/`onDestroy` — never written from anywhere else. `@Volatile`
 * for the same cross-thread-visibility reason as that class's own flags (see its doc).
 */
object PresenceServiceState {
    @Volatile
    var isRunning: Boolean = false
}
