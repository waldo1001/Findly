package com.findly.android.ui.designsystem.token

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.round

/**
 * A28 (specs/003-android-client.md §4.1–§4.2): a pure JVM unit test over the token tables that
 * computes real WCAG 2.1 contrast ratios and fails the build when a declared pairing drops below
 * its threshold, instead of trusting a hand-written table — which is exactly what A26's review
 * found wrong seven times in the design handoff, four of which would have shipped as real AA
 * failures with zero design-system tests to catch them
 * (`find mobile/android -name "*Test*.kt" | grep designsystem` returned nothing before this file).
 *
 * This app is used outdoors, in bright sun, by a parent looking for a child — contrast is a safety
 * property here, not a style preference.
 */
class ColorTokenContrastTest {

    @Test
    fun `every declared pairing clears its WCAG threshold`() {
        val failures = declaredColorPairings.mapNotNull { pairing ->
            val ratio = contrastRatio(pairing.foreground, pairing.background)
            if (ratio < pairing.threshold) {
                "  [${pairing.theme}] ${pairing.name}: measured ${round2(ratio)}:1, needs >= ${pairing.threshold}:1"
            } else {
                null
            }
        }

        assertTrue(
            "The following declared color-token pairings fail their WCAG 2.1 threshold " +
                "(specs/003-android-client.md §4.1–§4.2). This is either a real accessibility " +
                "regression in FindlyColorTokens, or a genuinely new failure that must be reported " +
                "rather than papered over per A28's scope note — do not adjust the threshold or the " +
                "value here without the orchestrator's sign-off:\n" +
                failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }

    // --- The four pairings A26's review measured as actual, shipped AA failures in the design
    // handoff's own contrast table. Pinned individually (not folded into declaredColorPairings)
    // so a future token change cannot silently reintroduce any of them; each documents both the
    // handoff's wrong claim and the corrected, shipped measurement. ---

    @Test
    fun `dark raw outline does NOT clear 3-to-1 against dark surface — this is why outlineStrong exists`() {
        // HANDOFF.md and the original specs/003 §4.2 text claimed "in dark, outline itself clears
        // 3:1 and serves both". Measured reality (A26 security review, ColorTokens.kt): 1.99:1.
        val rawOutlineRatio = contrastRatio(DarkFindlyColors.outline, DarkFindlyColors.surface)
        assertTrue(
            "dark `outline` (#3A4463) measured ${round2(rawOutlineRatio)}:1 against dark `surface` " +
                "(#0B0F1C) — expected it to stay BELOW 3:1 (HANDOFF.md wrongly claimed it clears " +
                "3:1; measured reality is 1.99:1). If this now passes, someone changed `outline` " +
                "without updating this pin — meaning-carrying strokes must keep pointing at " +
                "`outlineStrong`, not `outline`, in dark.",
            rawOutlineRatio < GRAPHICAL_MIN_RATIO,
        )

        // outlineStrong is the token that actually carries meaning-bearing strokes in dark instead.
        val outlineStrongRatio = contrastRatio(DarkFindlyColors.outlineStrong, DarkFindlyColors.surface)
        assertTrue(
            "dark `outlineStrong` (#6B739A) measured ${round2(outlineStrongRatio)}:1 against dark " +
                "`surface` — expected it to clear 3:1 (measured reality is 4.13:1). If this fails, " +
                "meaning-carrying strokes in dark have no working token left.",
            outlineStrongRatio >= GRAPHICAL_MIN_RATIO,
        )
    }

    @Test
    fun `dark marker pill fill is not light theme's success green — that measured 1point83 to 1 against dark primary`() {
        // HANDOFF.md asserted #52E39B "in BOTH themes ... 5.4:1 on #3A46C8" (light primary only).
        // Never checked against dark primary #7C8BFF, where it measures 1.83:1 and disappears.
        val oldFillOnDarkPrimary = contrastRatio(Color(0xFF52E39B), DarkFindlyColors.primary)
        assertTrue(
            "light theme's marker-pill fill #52E39B measured ${round2(oldFillOnDarkPrimary)}:1 " +
                "against dark `primary` (#7C8BFF) — expected it to stay BELOW 3:1 (measured reality " +
                "is 1.83:1), which is exactly why dark uses its own markerOnlineDot value instead.",
            oldFillOnDarkPrimary < GRAPHICAL_MIN_RATIO,
        )

        // The shipped dark fill, #0B3B26, measures 4.19:1 on dark primary.
        val shippedFillOnDarkPrimary = contrastRatio(DarkFindlyColors.markerOnlineDot, DarkFindlyColors.primary)
        assertTrue(
            "dark `markerOnlineDot` (#0B3B26) measured ${round2(shippedFillOnDarkPrimary)}:1 against " +
                "dark `primary` — expected it to clear 3:1 (measured reality is 4.19:1).",
            shippedFillOnDarkPrimary >= GRAPHICAL_MIN_RATIO,
        )
    }

    @Test
    fun `dark StatusChip online label uses the onDanger token, not a literal white — white measures 1point64 to 1`() {
        // HANDOFF.md's "onDanger-white text" phrasing for the online chip was read literally by one
        // platform (this one reads it as the onDanger TOKEN, which is #2A0708 in dark, not white —
        // see FindlyStatusChip.kt's doc comment). A literal white on dark `success` fails badly.
        val literalWhiteOnDarkSuccess = contrastRatio(Color(0xFFFFFFFF), DarkFindlyColors.success)
        assertTrue(
            "literal white on dark `success` (#52E39B) measured ${round2(literalWhiteOnDarkSuccess)}:1 " +
                "— expected it to stay BELOW 4.5:1 (measured reality is 1.64:1). If FindlyStatusChip " +
                "ever hardcodes white for the online tone's label instead of the onDanger token, this " +
                "assertion stops proving anything.",
            literalWhiteOnDarkSuccess < TEXT_MIN_RATIO,
        )

        // The actual token used, onDanger (#2A0708 in dark), measures 11.32:1 on dark success.
        val onDangerTokenOnDarkSuccess = contrastRatio(DarkFindlyColors.onDanger, DarkFindlyColors.success)
        assertTrue(
            "dark `onDanger` (#2A0708) on dark `success` (#52E39B) measured " +
                "${round2(onDangerTokenOnDarkSuccess)}:1 — expected it to clear 4.5:1 (measured " +
                "reality is 11.32:1). This is the token FindlyStatusChip's Success tone actually uses.",
            onDangerTokenOnDarkSuccess >= TEXT_MIN_RATIO,
        )
    }

    @Test
    fun `dark buttonPrimaryPressedFill is not HANDOFFs light-only literal — that measured 1point93 to 1`() {
        // HANDOFF.md gives only one hex ("Pressed: fill #2C36A0"), implicitly light-only. Applied
        // unchanged in dark, dark onPrimary (#0A0F27, near-black) sits at 1.93:1 on it — fails
        // normal-text AA (the button label is 16sp/600, not WCAG's "large text").
        val handoffLightLiteralInDark = contrastRatio(DarkFindlyColors.onPrimary, Color(0xFF2C36A0))
        assertTrue(
            "dark `onPrimary` (#0A0F27) on HANDOFF.md's light-only pressed-fill literal (#2C36A0) " +
                "measured ${round2(handoffLightLiteralInDark)}:1 — expected it to stay BELOW 4.5:1 " +
                "(measured reality is 1.93:1), which is why dark needs its own pressed-fill value.",
            handoffLightLiteralInDark < TEXT_MIN_RATIO,
        )

        // The shipped dark value, #6D7AE0 (a shallower darken of dark primary), measures 4.96:1.
        val shippedDarkFill = contrastRatio(DarkFindlyColors.onPrimary, DarkFindlyColors.buttonPrimaryPressedFill)
        assertTrue(
            "dark `onPrimary` on the shipped dark `buttonPrimaryPressedFill` (#6D7AE0) measured " +
                "${round2(shippedDarkFill)}:1 — expected it to clear 4.5:1 (measured reality is " +
                "4.96:1).",
            shippedDarkFill >= TEXT_MIN_RATIO,
        )
    }

    // --- Documented decorative exemption: legal below 3:1 because it is never used for a
    // meaning-carrying stroke (outlineStrong is, for those). Encoded explicitly, per A28's filing,
    // "so the test states the rule instead of silently ignoring the token". ---

    @Test
    fun `light outline is a documented decorative-only exemption below 3-to-1 — hairlines and dividers, never a meaning-carrying stroke`() {
        val ratio = contrastRatio(LightFindlyColors.outline, LightFindlyColors.surface)
        assertEquals(
            "light `outline` (#A9B0CE) on light `surface` (#F2F4FB) expected ~1.95:1 (legal only " +
                "because `outline` is documented as decorative-hairline-only in specs/003 §4.2; any " +
                "stroke that carries meaning must use `outlineStrong` instead — see the other tests " +
                "in this file). Got ${round2(ratio)}:1.",
            1.95,
            ratio,
            0.05,
        )
    }

    private fun round2(value: Double): Double = round(value * 100) / 100
}
