package com.findly.android.location.settings

/**
 * specs/009-device-runtime.md §3.2 "Restart and recovery": [BootCompletedReceiver] MUST react
 * only to `ACTION_BOOT_COMPLETED` and `ACTION_MY_PACKAGE_REPLACED` — the two explicit
 * start-from-background exemptions the OS grants for this purpose — and ignore anything else.
 *
 * Pure so this gate is unit-tested without a `BroadcastReceiver`/`Intent` in the loop
 * (code-review fix, finding 3, post-A40 review): the action strings are the exact literal values
 * of `Intent.ACTION_BOOT_COMPLETED` / `Intent.ACTION_MY_PACKAGE_REPLACED` — spelled out here
 * rather than importing `android.content.Intent` so this class stays zero-`android.*`, matching
 * every other decision seam in this package (`ServiceRestartDecision`,
 * `CachedScheduleReapplyDecision`).
 */
object BootCompletedActionGate {
    private const val ACTION_BOOT_COMPLETED = "android.intent.action.BOOT_COMPLETED"
    private const val ACTION_MY_PACKAGE_REPLACED = "android.intent.action.MY_PACKAGE_REPLACED"

    fun shouldReapply(action: String?): Boolean =
        action == ACTION_BOOT_COMPLETED || action == ACTION_MY_PACKAGE_REPLACED
}
