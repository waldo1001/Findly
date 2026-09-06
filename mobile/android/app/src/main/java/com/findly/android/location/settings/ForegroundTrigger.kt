package com.findly.android.location.settings

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
 */
class ForegroundTrigger(
    private val poll: suspend () -> Unit,
    private val runOnce: suspend () -> Unit,
) {
    suspend fun run() {
        poll()
        runOnce()
    }
}
