package com.findly.android.location.settings

import kotlinx.coroutines.CancellationException

/**
 * specs/009-device-runtime.md §1.4 "Foreground use is a trigger": "on every app foreground both
 * platforms MUST run one full sync cycle... in addition to the paused-device settings poll" — the
 * settings poll runs first so a resume-from-pause observed here takes effect for the very same
 * foreground's capture attempt ([com.findly.android.AppContainer.onAppForeground]'s doc).
 *
 * Pure so this ordering ("poll, then runOnce, exactly once per foreground") is unit-tested without
 * a `Context`/coroutine dispatcher in the loop — code-review fix (finding 3, post-A40 review): the
 * A40 commit wired this sequence directly into `AppContainer.onAppForeground` with zero test
 * coverage even though every other §12 checklist line in scope was covered.
 *
 * Round-3 post-A40 review (finding 5): a throwing [poll] must not cost the foreground its
 * [runOnce] cycle — the full sync cycle is the more valuable half of this pair (specs/009 §1.4),
 * so [poll]'s failure is swallowed here rather than propagating and skipping [runOnce].
 * [CancellationException] is rethrown, never swallowed, so structured concurrency on the caller's
 * scope is preserved.
 */
class ForegroundTrigger(
    private val poll: suspend () -> Unit,
    private val runOnce: suspend () -> Unit,
) {
    suspend fun run() {
        try {
            poll()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Defensive only - poll() never throws in the real DeviceSettingsCoordinator/
            // SettingsPoller path (specs/009 §4/§9 route every failure to a PollOutcome). Any
            // uncaught throw here would otherwise still reach AppContainer.applicationScope's
            // CoroutineExceptionHandler (finding 1) rather than crash the process, but skipping
            // runOnce on a poll hiccup is unnecessary, so it is absorbed at the source instead.
        }
        runOnce()
    }
}
