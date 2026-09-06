package com.findly.android.queue.worker

/**
 * specs/009-device-runtime.md §3.2's Doze-safe tick: what `LocationForegroundService` schedules
 * as its *next* `AlarmManager.setAndAllowWhileIdle` wakeup after one [RunResult] — a full
 * `syncIntervalMinutes` away on [RunResult.Success] (attempt counter reset for the next backoff
 * sequence), or [BackoffPolicy]'s exponential delay for the current attempt on [RunResult.Retry]
 * (§9: "capped at the sync interval"). Pure so the attempt bookkeeping is unit-tested without an
 * `AlarmManager`/`Service` in the loop; the delay formula itself is unchanged, existing,
 * [BackoffPolicy].
 */
object ServiceTickPolicy {
    data class NextTick(val delayMillis: Long, val nextAttempt: Int)

    /** [attempt] is 1-based, same convention as [BackoffPolicy.delayMillisForAttempt]. */
    fun next(result: RunResult, attempt: Int, syncIntervalMinutes: Int): NextTick = when (result) {
        RunResult.Success -> NextTick(
            delayMillis = syncIntervalMinutes * MILLIS_PER_MINUTE,
            nextAttempt = 1,
        )
        RunResult.Retry -> NextTick(
            delayMillis = BackoffPolicy.delayMillisForAttempt(attempt, syncIntervalMinutes),
            nextAttempt = attempt + 1,
        )
    }

    private const val MILLIS_PER_MINUTE = 60_000L
}
