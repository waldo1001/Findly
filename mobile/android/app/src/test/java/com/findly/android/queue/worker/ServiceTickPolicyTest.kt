package com.findly.android.queue.worker

import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §3.2's Doze-safe tick / §9's backoff: what
 * `LocationForegroundService` schedules for its *next* `AlarmManager.setAndAllowWhileIdle` tick
 * after one `runOnce` cycle. Pure so the attempt-counter/backoff wiring is unit-tested without an
 * `AlarmManager` in the loop; the actual delay formula stays [BackoffPolicy]'s (§9: "capped at the
 * sync interval"), unchanged by this task. */
class ServiceTickPolicyTest {

    @Test
    fun `success - next tick is one full interval away, attempt resets to 1`() {
        val next = ServiceTickPolicy.next(RunResult.Success, attempt = 3, syncIntervalMinutes = 5)

        assertEquals(5 * 60_000L, next.delayMillis)
        assertEquals(1, next.nextAttempt)
    }

    @Test
    fun `retry - next tick uses BackoffPolicy for the current attempt, attempt increments`() {
        val next = ServiceTickPolicy.next(RunResult.Retry, attempt = 1, syncIntervalMinutes = 10)

        assertEquals(BackoffPolicy.delayMillisForAttempt(1, 10), next.delayMillis)
        assertEquals(2, next.nextAttempt)
    }

    @Test
    fun `retry - backoff never exceeds the sync interval, even at a high attempt count`() {
        val next = ServiceTickPolicy.next(RunResult.Retry, attempt = 20, syncIntervalMinutes = 5)

        assertEquals(5 * 60_000L, next.delayMillis)
        assertEquals(21, next.nextAttempt)
    }
}
