package com.findly.android.ui.map

/**
 * specs/010-app-shell-and-screen-ux.md §3.1/§10: pure, shared-logic humanization of a roster row's
 * `recordedAt` (001-api-contract.md §1.4, ISO 8601 UTC) — replaces the raw ISO strings both
 * platforms show today. `nowIso` is an explicit parameter (mirrors [GroupCountdownFormatter]'s
 * `now`-as-parameter shape) so the ticker that recomputes this every 30 s (`MapScreen`) can drive
 * it deterministically and so this stays unit-testable with no clock/Android dependency.
 *
 * RED-before-GREEN placeholder (devloop/A34): intentionally wrong so `RelativeTimeFormatterTest`
 * fails for a real reason, not a compile error, before the real thresholds below are implemented.
 */
object RelativeTimeFormatter {
    fun format(recordedAtIso: String, nowIso: String): String = "TODO"
}
