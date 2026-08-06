package com.findly.android.ui.designsystem.token

import androidx.compose.ui.graphics.Color

/**
 * WCAG 2.1 contrast-ratio math (test-only support for A28, specs/003-android-client.md §4.1–§4.2).
 *
 * There is no shipped-app call site for this — it exists purely to let
 * [ColorTokenContrastTest] (and friends) compute real contrast ratios over the actual
 * [com.findly.android.ui.designsystem.token.FindlyColorTokens] values instead of trusting a
 * hand-written table, which is exactly the trap A26's review found: the design handoff's own
 * contrast column was wrong seven times, four of which shipped as real AA failures. Per A28's
 * scope, this stays under `app/src/test/` — it is not added to the shipped app.
 *
 * TODO(A28 red commit): this is a deliberately wrong stub — [contrastRatio] always returns 1.0 —
 * so that [ContrastRatioReferenceTest] and [ColorTokenContrastTest] are proven to fail for real
 * before the actual formula is implemented (red-before-green, visible in git log per the process
 * this task mandates). The next commit replaces this with the real relative-luminance formula.
 */
fun relativeLuminance(color: Color): Double {
    TODO("A28 red commit: not implemented yet — see ContrastRatio.kt")
}

fun contrastRatio(foreground: Color, background: Color): Double = 1.0
