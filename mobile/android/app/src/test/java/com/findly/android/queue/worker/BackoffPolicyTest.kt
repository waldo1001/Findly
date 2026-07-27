package com.findly.android.queue.worker

import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §9: exponential, 30s initial, doubling, capped at the sync interval. */
class BackoffPolicyTest {

    @Test
    fun `attempt 1 is the 30s initial delay`() {
        assertEquals(30_000L, BackoffPolicy.delayMillisForAttempt(1, syncIntervalMinutes = 60))
    }

    @Test
    fun `each attempt doubles the previous one`() {
        assertEquals(30_000L, BackoffPolicy.delayMillisForAttempt(1, syncIntervalMinutes = 120))
        assertEquals(60_000L, BackoffPolicy.delayMillisForAttempt(2, syncIntervalMinutes = 120))
        assertEquals(120_000L, BackoffPolicy.delayMillisForAttempt(3, syncIntervalMinutes = 120))
        assertEquals(240_000L, BackoffPolicy.delayMillisForAttempt(4, syncIntervalMinutes = 120))
    }

    @Test
    fun `never exceeds the sync interval, even after many attempts`() {
        val capMillis = 15 * 60_000L

        assertEquals(capMillis, BackoffPolicy.delayMillisForAttempt(10, syncIntervalMinutes = 15))
        assertEquals(capMillis, BackoffPolicy.delayMillisForAttempt(1000, syncIntervalMinutes = 15))
    }

    @Test
    fun `the cap tracks whatever sync interval is passed`() {
        assertEquals(5 * 60_000L, BackoffPolicy.delayMillisForAttempt(10, syncIntervalMinutes = 5))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `attempt below 1 is rejected`() {
        BackoffPolicy.delayMillisForAttempt(0, syncIntervalMinutes = 15)
    }
}
