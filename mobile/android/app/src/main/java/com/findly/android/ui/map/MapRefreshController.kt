package com.findly.android.ui.map

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** What caused a fetch (specs/010-app-shell-and-screen-ux.md §3.6). */
enum class RefreshTrigger { Initial, Visible, Timer, Explicit }

/** One fetch in progress. */
class RefreshRun(val trigger: RefreshTrigger) {
    var explicit: Boolean = trigger == RefreshTrigger.Explicit
        internal set
}

/**
 * RED SKELETON (A55): behaves like the pre-A55 holders — one unconditional fetch per call, no
 * timer, no visibility handling, no in-flight gate — so the new tests fail on the shipped bug.
 */
class MapRefreshController(
    private val scope: CoroutineScope,
    @Suppress("unused") private val intervalMillis: Long = REFRESH_INTERVAL_MILLIS,
    private val fetch: suspend (RefreshRun) -> Unit,
) {
    fun start() {
        scope.launch { request(RefreshTrigger.Initial) }
    }

    fun onVisible() {}

    fun onHidden() {}

    suspend fun request(trigger: RefreshTrigger): Boolean {
        fetch(RefreshRun(trigger))
        return true
    }

    companion object {
        const val REFRESH_INTERVAL_MILLIS = 30_000L
    }
}
