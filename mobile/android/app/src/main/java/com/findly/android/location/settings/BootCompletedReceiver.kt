package com.findly.android.location.settings

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.findly.android.FindlyApplication
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * specs/009-device-runtime.md §3.2 "Restart and recovery": `ACTION_BOOT_COMPLETED` and
 * `ACTION_MY_PACKAGE_REPLACED` are both explicit Android start-from-background exemptions for a
 * location foreground service — "the app MUST declare `RECEIVE_BOOT_COMPLETED` and a receiver...
 * that re-applies the current schedule". Thin, untested Android-framework glue by design; the
 * action check itself is [BootCompletedActionGate] (pure, unit-tested), and the "what does
 * re-apply mean" decision lives in [CachedScheduleReapplyDecision], reached via the single
 * [com.findly.android.AppContainer.reapplyCachedScheduleSuspending] entry point that cold start
 * ([com.findly.android.AppContainer.start]) and every foreground
 * ([com.findly.android.AppContainer.onActivityStarted]) also reach — one implementation of
 * "read the cache, reschedule if tracking is on", not three.
 *
 * **Code-review fix (finding 1, post-A40 review): runs inside `goAsync()`.** The previous version
 * dispatched onto `AppContainer`'s own `applicationScope` and returned immediately, which lets the
 * foreground-service start land *after* this broadcast's temporary background-start allowlist
 * window has already closed — forfeiting the very exemption `ACTION_BOOT_COMPLETED` grants. Doing
 * the cached read + reschedule inside the `PendingResult` this receiver holds via `goAsync()`
 * keeps the work inside that window; the result is released in a `finally` so the OS can recycle
 * the receiver whether the work succeeds, no-ops, or any part of it fails.
 *
 * Round-3 post-A40 review (finding 4): this `try`/`finally` had no `catch` — it relied on
 * [com.findly.android.AppContainer.reapplyCachedScheduleSuspending] to swallow failures, but that
 * function used to wrap only its `reschedule` call, not the cached-settings read or the reapply
 * decision ahead of it. A throw from either of those propagated out through this `finally` into
 * the plain `CoroutineScope(Dispatchers.Default)` below, which carried no
 * `CoroutineExceptionHandler`, killing the process during boot. Fixed at the source:
 * [com.findly.android.AppContainer.reapplyCachedScheduleSuspending] now wraps its entire body, so
 * every failure short of [kotlinx.coroutines.CancellationException] is swallowed (and logged by
 * exception class name only) before it can reach this receiver's caller.
 *
 * **A42 (docs/implementation-handoff.md) sweep, finding 1:** the scope below still had no
 * [CoroutineExceptionHandler] of its own — belt-and-braces against a bug in
 * [com.findly.android.AppContainer.reapplyCachedScheduleSuspending] itself (or a future edit that
 * narrows its own catch), or a throw from `container` construction/access before that call is even
 * reached, either of which would otherwise still kill the process during boot exactly as this
 * class's own doc above once diagnosed. Logs the exception's class name only, never its
 * message/cause (specs/009-device-runtime.md §9: counts and error codes only, never
 * coordinates/`deviceId`/tokens/phone numbers).
 */
class BootCompletedReceiver : BroadcastReceiver() {

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        Log.d(TAG, "unhandled boot-reapply coroutine failure (${throwable::class.simpleName})")
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (!BootCompletedActionGate.shouldReapply(intent.action)) return

        val container = (context.applicationContext as FindlyApplication).container
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.Default + exceptionHandler).launch {
            try {
                container.reapplyCachedScheduleSuspending()
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        const val TAG = "FindlySync"
    }
}
