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
 * Formula: WCAG 2.1 §1.4.3 relative luminance — linearize each sRGB channel (divide by 12.92 below
 * the 0.03928 threshold, otherwise `((c + 0.055) / 1.055) ^ 2.4`), then
 * `L = 0.2126*R + 0.7152*G + 0.0722*B`. Contrast ratio is `(L1 + 0.05) / (L2 + 0.05)` with L1 the
 * lighter of the two relative luminances. [ContrastRatioReferenceTest] pins this against the
 * published `#767676` on `#FFFFFF` = 4.54:1 reference value.
 */
fun relativeLuminance(color: Color): Double {
    fun linearize(channel: Float): Double {
        val c = channel.toDouble()
        return if (c <= 0.03928) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(color.red) + 0.7152 * linearize(color.green) + 0.0722 * linearize(color.blue)
}

fun contrastRatio(foreground: Color, background: Color): Double {
    val l1 = relativeLuminance(foreground)
    val l2 = relativeLuminance(background)
    val lighter = maxOf(l1, l2)
    val darker = minOf(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}
