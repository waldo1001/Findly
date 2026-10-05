package com.findly.android.ui.map

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What caused a fetch (specs/010-app-shell-and-screen-ux.md §3.6). */
enum class RefreshTrigger {
    /** First appearance of the screen — the holder's own `init` load. */
    Initial,

    /** A return to the foreground while the map is the visible screen, or a navigation back to the
     * map from another screen (010 §3.6 bullet 2). */
    Visible,

    /** The 30 s timer, which only ticks while the map is visible **and** foregrounded (bullet 3). */
    Timer,

    /** The user's own Refresh / Retry tap. */
    Explicit,
}

/**
 * One fetch in progress, handed to the controller's `fetch` callback. The callback consults
 * [explicit] **when the response arrives** (not when the request started) to decide whether a
 * failure is surfaced: an explicit Refresh "still reports its own failure" (010 §3.6), while a
 * periodic or foreground failure is silent.
 */
class RefreshRun(val trigger: RefreshTrigger) {
    /** True for an explicit Refresh — and flips to true if one is [adopted][MapRefreshController.request]
     * while this fetch is already running. */
    @Volatile
    var explicit: Boolean = trigger == RefreshTrigger.Explicit
        internal set
}

/**
 * The pure trigger policy of specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59): WHEN the
 * family map (and, per §3.2, the group map) re-fetches its positions. No Android or Compose
 * dependency — the timer is an injected-[scope] `delay` loop, so tests drive it with
 * `kotlinx-coroutines-test` virtual time; the only lifecycle wiring is `MapRoute`'s/
 * `GroupMapRoute`'s `LifecycleResumeEffect` calling [onVisible]/[onHidden]. WHAT a fetch does with
 * its response (keep-last-data on a silent failure, camera, selection) is the holder's concern, not
 * this class's.
 *
 * The rules (010 §3.6):
 * 1. **First appearance** — [start] fetches once, immediately ([RefreshTrigger.Initial]). The first
 *    [onVisible] after it is the *same* appearance, so it only starts the timer — no second fetch.
 * 2. **Every return to visible + foregrounded** — [onVisible] (after a [onHidden]) fetches at once
 *    ([RefreshTrigger.Visible]). The caller passes "visible and foregrounded" as a single signal:
 *    the map's `NavBackStackEntry` lifecycle being `RESUMED` (true only while it is the top
 *    destination *and* the activity is resumed).
 * 3. **Every [intervalMillis] while visible** — [RefreshTrigger.Timer], restarted from each
 *    [onVisible]. [onHidden] stops it, so **nothing is ever fetched in the background**. A fetch
 *    already in flight when the screen is hidden is left to finish (it started while visible).
 * 4. **At most one request in flight** — a trigger arriving while one runs is dropped, never
 *    queued. The one refinement: a dropped [RefreshTrigger.Explicit] *adopts* the running fetch
 *    ([RefreshRun.explicit] becomes true), so that fetch's failure is reported as the user's
 *    Refresh's own instead of vanishing as a silent tick.
 * 5. **A confirmed state change ends polling** — the holder calls [endPolling] when a response is
 *    one (010 §3.6): the timer stops for good and [onVisible] no longer fetches or ticks. The
 *    user's own explicit Retry still fetches.
 *
 * Threading: driven from the main thread (`viewModelScope` is `Dispatchers.Main.immediate`); the
 * small amount of shared state is nevertheless guarded, and the lock is never held across a
 * suspension.
 */
class MapRefreshController(
    private val scope: CoroutineScope,
    private val intervalMillis: Long = REFRESH_INTERVAL_MILLIS,
    private val fetch: suspend (RefreshRun) -> Unit,
) {
    private val lock = Any()
    private var inFlight: RefreshRun? = null
    private var visible = false
    private var firstVisibleCovered = false
    private var timerJob: Job? = null
    private var pollingEnded = false

    /** First appearance: fetches once, immediately. Call exactly once, from the holder's `init`. */
    fun start() {
        synchronized(lock) { firstVisibleCovered = true }
        scope.launch { request(RefreshTrigger.Initial) }
    }

    /** The screen became visible **and** foregrounded. Idempotent while already visible. */
    fun onVisible() {
        val fetchNow: Boolean
        synchronized(lock) {
            if (visible) return
            visible = true
            if (pollingEnded) return
            // The first onVisible after start() is the first appearance, which the initial load
            // already covers — it must not fetch a second time.
            fetchNow = !firstVisibleCovered
            firstVisibleCovered = false
            timerJob?.cancel()
            timerJob = null
        }
        // Launched outside the lock; the timer starts from *this* moment, never resuming an older
        // schedule.
        val timer = scope.launch { tickLoop() }
        val endedMeanwhile = synchronized(lock) {
            if (pollingEnded) true else { timerJob = timer; false }
        }
        if (endedMeanwhile) timer.cancel()
        if (fetchNow) scope.launch { request(RefreshTrigger.Visible) }
    }

    /** The screen stopped being visible, or the app left the foreground: stop the timer. An
     * in-flight fetch is not cancelled. */
    fun onHidden() {
        val timer = synchronized(lock) {
            visible = false
            timerJob.also { timerJob = null }
        }
        timer?.cancel()
    }

    /**
     * Ends **polling** for this screen for good (010 §3.6: a confirmed state change "ends polling
     * for that screen"): cancels the timer and drops every later [RefreshTrigger.Visible] /
     * [RefreshTrigger.Timer] request, so neither a foreground return nor the 30 s tick fetches
     * again. An explicit request ([RefreshTrigger.Explicit] — the user's own Retry) still runs: a
     * tap is not polling. Idempotent.
     */
    fun endPolling() {
        val timer = synchronized(lock) {
            pollingEnded = true
            timerJob.also { timerJob = null }
        }
        timer?.cancel()
    }

    /**
     * Runs a fetch for [trigger] unless one is already in flight, in which case it is dropped (and,
     * for [RefreshTrigger.Explicit], adopts the running fetch — see the class doc). Suspends until
     * the fetch it ran completes. Returns whether this call ran a fetch. The in-flight gate always
     * reopens, including when the fetch is cancelled or throws.
     */
    suspend fun request(trigger: RefreshTrigger): Boolean {
        val run = RefreshRun(trigger)
        synchronized(lock) {
            // Polling ended (a confirmed state change): the automatic triggers are dead, including
            // one that was already launched and is only now reaching the gate.
            if (pollingEnded && (trigger == RefreshTrigger.Visible || trigger == RefreshTrigger.Timer)) return false
            val running = inFlight
            if (running != null) {
                if (trigger == RefreshTrigger.Explicit) running.explicit = true
                return false
            }
            inFlight = run
        }
        try {
            fetch(run)
        } finally {
            synchronized(lock) { if (inFlight === run) inFlight = null }
        }
        return true
    }

    private suspend fun tickLoop() {
        while (true) {
            delay(intervalMillis)
            // A separate coroutine, not awaited here: hiding cancels this loop (no more ticks) but
            // must not cancel a fetch that is already running.
            scope.launch { request(RefreshTrigger.Timer) }
        }
    }

    companion object {
        /** specs/010 §3.6: one `GET` per 30 s of viewing. */
        const val REFRESH_INTERVAL_MILLIS = 30_000L
    }
}
