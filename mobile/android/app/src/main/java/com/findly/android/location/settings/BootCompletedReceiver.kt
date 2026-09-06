package com.findly.android.location.settings

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.findly.android.FindlyApplication
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
 * the receiver whether the work succeeds, no-ops, or the reschedule itself fails (swallowed by
 * [com.findly.android.AppContainer.reapplyCachedScheduleSuspending], per finding 1's other half).
 */
class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!BootCompletedActionGate.shouldReapply(intent.action)) return

        val container = (context.applicationContext as FindlyApplication).container
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                container.reapplyCachedScheduleSuspending()
            } finally {
                pendingResult.finish()
            }
        }
    }
}
