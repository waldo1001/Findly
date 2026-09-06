package com.findly.android.queue.worker

/**
 * specs/009-device-runtime.md §3.5 ("if `syncIntervalMinutes` changed the schedule MUST be
 * rebuilt immediately"), applied to the already-running §3.2 foreground service: what
 * `LocationForegroundService.onStartCommand` does when a fresh `EXTRA_SYNC_INTERVAL_MINUTES`
 * arrives.
 *
 * Pure so this "same interval while running is a no-op, any other case starts a fresh cycle" rule
 * is unit-tested without a `Service`/`Intent` in the loop — code-review fix (finding 4, post-A40
 * review): the A40 commit gated this on [cycleStarted] alone, so an interval change arriving
 * while a cycle was already running (e.g. 5 -> 10 mid-cycle) was silently dropped — the service
 * kept ticking at the stale interval baked into the already-scheduled `AlarmManager` tick.
 */
object ForegroundCycleRestartDecision {
    sealed class Action {
        data object Ignore : Action()
        data object StartFreshCycle : Action()
    }

    /**
     * @param cycleStarted whether a cycle has ever been started for this service instance.
     * @param currentSyncIntervalMinutes the interval the running/most-recently-started cycle
     * uses, or `null` before the first cycle.
     * @param incomingSyncIntervalMinutes the interval carried by the just-received start `Intent`.
     */
    fun decide(
        cycleStarted: Boolean,
        currentSyncIntervalMinutes: Int?,
        incomingSyncIntervalMinutes: Int,
    ): Action = if (!cycleStarted || incomingSyncIntervalMinutes != currentSyncIntervalMinutes) {
        Action.StartFreshCycle
    } else {
        Action.Ignore
    }
}
