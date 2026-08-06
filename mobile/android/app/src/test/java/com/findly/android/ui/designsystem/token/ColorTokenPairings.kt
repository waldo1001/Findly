package com.findly.android.ui.designsystem.token

import androidx.compose.ui.graphics.Color

/** WCAG 2.1 minimum for body text (specs/003-android-client.md §4.2, A28 filing). */
const val TEXT_MIN_RATIO = 4.5

/** WCAG 2.1 minimum for meaningful strokes/graphical objects and component-level fills (A28
 * filing) — large text also qualifies at this threshold, but nothing declared here relies on the
 * large-text exception; every text pairing below is held to [TEXT_MIN_RATIO] instead. */
const val GRAPHICAL_MIN_RATIO = 3.0

/** One declared token pairing this app relies on for accessibility, resolved for one theme. Add a
 * new pairing here — not new test code — when a new token combination ships (A28,
 * specs/003-android-client.md §4.1–§4.2: "Encode the pairings as data, so adding a token pairing
 * is a data edit, not new test code"). */
data class ColorPairing(
    val name: String,
    val theme: String,
    val threshold: Double,
    val foreground: Color,
    val background: Color,
)

private fun textPairing(name: String, theme: String, fg: Color, bg: Color) =
    ColorPairing(name, theme, TEXT_MIN_RATIO, fg, bg)

private fun graphicalPairing(name: String, theme: String, fg: Color, bg: Color) =
    ColorPairing(name, theme, GRAPHICAL_MIN_RATIO, fg, bg)

/**
 * Every pairing A28 (specs/003-android-client.md §4.1–§4.2) requires to clear its WCAG 2.1
 * threshold, in both themes. [ColorTokenContrastTest] asserts every entry here passes; the four
 * pairings that were measured to actually FAIL against the design handoff's own claims (dark
 * `outline`, the old dark marker-pill fill, a literal white on dark `success`, and HANDOFF's
 * light-only `buttonPrimaryPressedFill` literal in dark) are pinned as their own explicit,
 * separately-named tests in [ColorTokenContrastTest] instead of being listed here — this table is
 * exclusively the "must always pass" contract.
 */
val declaredColorPairings: List<ColorPairing> = buildList {
    for ((theme, colors) in listOf("light" to LightFindlyColors, "dark" to DarkFindlyColors)) {
        // --- Text pairs, 4.5:1 ---
        add(textPairing("onPrimary on primary", theme, colors.onPrimary, colors.primary))
        add(textPairing("onSurface on surface", theme, colors.onSurface, colors.surface))
        add(textPairing("onSurface on surfaceVariant", theme, colors.onSurface, colors.surfaceVariant))
        add(textPairing("onDanger on danger", theme, colors.onDanger, colors.danger))
        add(textPairing("subtleText on surface", theme, colors.subtleText, colors.surface))
        add(textPairing("subtleText on surfaceVariant", theme, colors.subtleText, colors.surfaceVariant))
        add(textPairing("success used as text on surface", theme, colors.success, colors.surface))
        add(textPairing("warning used as text on surface", theme, colors.warning, colors.surface))
        add(textPairing("danger used as text on surface", theme, colors.danger, colors.surface))

        // --- Meaningful strokes / graphical objects, 3:1 ---
        add(graphicalPairing("outlineStrong vs surface", theme, colors.outlineStrong, colors.surface))
        add(graphicalPairing("outlineStrong vs surfaceVariant", theme, colors.outlineStrong, colors.surfaceVariant))
        // FindlyMapMarkerBubble's "NOW" pill fill sits on the primary bubble background.
        add(graphicalPairing("marker pill fill (markerOnlineDot) against primary", theme, colors.markerOnlineDot, colors.primary))
        // FindlyStatusChip's Neutral/paused tone: transparent fill, outlineStrong border, sitting
        // on whatever surface it's placed on — same colors as the outlineStrong/surface pairing
        // above, named separately because it's a distinct UI element the A28 filing calls out by
        // name, not because the numbers differ.
        add(graphicalPairing("paused-chip (FindlyStatusChip Neutral) border vs surface", theme, colors.outlineStrong, colors.surface))

        // --- Component-level pairs, 4.5:1 (label text on its own fill) ---
        add(textPairing("FindlyStatusChip Success label (onDanger) on fill (success)", theme, colors.onDanger, colors.success))
        add(textPairing("FindlyStatusChip Warning label (onDanger) on fill (warning)", theme, colors.onDanger, colors.warning))
        add(textPairing("FindlyStatusChip Danger label (onDanger) on fill (danger)", theme, colors.onDanger, colors.danger))
        add(textPairing("marker pill label (markerOnlineDotOn) on pill fill (markerOnlineDot)", theme, colors.markerOnlineDotOn, colors.markerOnlineDot))
        add(textPairing("buttonPrimaryPressedFill vs onPrimary", theme, colors.onPrimary, colors.buttonPrimaryPressedFill))
    }
}
