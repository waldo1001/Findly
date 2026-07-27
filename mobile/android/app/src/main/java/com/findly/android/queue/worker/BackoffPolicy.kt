package com.findly.android.queue.worker

/**
 * Transient-flush-failure backoff (specs/009-device-runtime.md §9): exponential, 30 s initial,
 * doubling, **capped at the sync interval** ("never back off past the next natural capture").
 * WorkManager's own `setBackoffCriteria` implements this natively for the ≥15-minute path
 * (§3.1) — this pure calculator is for the §3.2 foreground-service path, whose self-rescheduling
 * timer isn't WorkManager-driven and so needs its own backoff bookkeeping.
 */
object BackoffPolicy {
    private const val INITIAL_DELAY_MILLIS = 30_000L
    private const val MAX_SHIFT = 20 // guards against Long overflow on a pathologically large attempt count

    /** [attempt] is 1-based (the first retry is attempt 1). */
    fun delayMillisForAttempt(attempt: Int, syncIntervalMinutes: Int): Long {
        require(attempt >= 1) { "attempt must be >= 1, was $attempt" }
        val capMillis = syncIntervalMinutes * 60_000L
        val shift = (attempt - 1).coerceAtMost(MAX_SHIFT)
        val exponential = INITIAL_DELAY_MILLIS * (1L shl shift)
        return exponential.coerceAtMost(capMillis)
    }
}
