package com.findly.android.queue.worker

import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §3.5: "if `syncIntervalMinutes` changed the schedule MUST be
 * rebuilt immediately" — including inside an already-running §3.2 foreground-service cycle.
 * Code-review fix (finding 4, post-A40 review): pins that a changed interval mid-cycle is no
 * longer silently dropped. */
class ForegroundCycleRestartDecisionTest {

    @Test
    fun `no cycle started yet - start fresh regardless of interval`() {
        assertEquals(
            ForegroundCycleRestartDecision.Action.StartFreshCycle,
            ForegroundCycleRestartDecision.decide(cycleStarted = false, currentSyncIntervalMinutes = null, incomingSyncIntervalMinutes = 5),
        )
    }

    @Test
    fun `same interval while a cycle is running - ignore (redundant startForegroundService)`() {
        assertEquals(
            ForegroundCycleRestartDecision.Action.Ignore,
            ForegroundCycleRestartDecision.decide(cycleStarted = true, currentSyncIntervalMinutes = 5, incomingSyncIntervalMinutes = 5),
        )
    }

    @Test
    fun `different interval while a cycle is running - start fresh (5 to 10)`() {
        assertEquals(
            ForegroundCycleRestartDecision.Action.StartFreshCycle,
            ForegroundCycleRestartDecision.decide(cycleStarted = true, currentSyncIntervalMinutes = 5, incomingSyncIntervalMinutes = 10),
        )
    }
}
