package com.findly.android.pushmessages

/** The three outcomes of specs/009-device-runtime.md §5.1's "Android execution model" handoff. */
sealed class LocateHandoffDecision {
    /** The §3.2 presence service is already a foregrounded location service — reuse it, no
     * second `FOREGROUND_SERVICE_LOCATION`. */
    data object UsePresenceService : LocateHandoffDecision()

    /** Start the short-lived `FOREGROUND_SERVICE_LOCATION` service (Android 12+'s explicit
     * high-priority-FCM-message exemption). */
    data object StartForegroundService : LocateHandoffDecision()

    /** Best-effort, possibly-late fallback — B26's 10-minute fulfil grace tolerates it. */
    data object ExpeditedWorkManager : LocateHandoffDecision()
}

/**
 * The pure decision behind specs/009-device-runtime.md §5.1's three ordered options —
 * `FindlyMessagingService`/`LocateRequestHandoff` carry out whichever this returns, but never
 * decide it themselves. Order is normative:
 *
 * 1. If the §3.2 presence service is already running, reuse it — it is already a foregrounded
 *    location service, so starting a second one would be redundant regardless of this message's
 *    own priority or permission state.
 * 2. Otherwise, a non-demoted (`PRIORITY_HIGH`) message with `ACCESS_BACKGROUND_LOCATION` granted
 *    starts the short-lived foreground service.
 * 3. Everything else (demoted priority, or background permission absent) falls back to expedited
 *    WorkManager.
 */
object LocateHandoffPolicy {
    fun decide(
        isHighPriority: Boolean,
        backgroundLocationGranted: Boolean,
        presenceServiceRunning: Boolean,
    ): LocateHandoffDecision = when {
        presenceServiceRunning -> LocateHandoffDecision.UsePresenceService
        isHighPriority && backgroundLocationGranted -> LocateHandoffDecision.StartForegroundService
        else -> LocateHandoffDecision.ExpeditedWorkManager
    }
}
