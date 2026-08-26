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

    // A31 addendum: the floor-only check right below (`every declared pairing clears its WCAG
    // threshold`) is necessary but not sufficient on its own — it cannot distinguish a pairing
    // that quietly drifted (while still clearing AA) from one that never moved, which is exactly
    // how A30 shipped: light `subtleText` measured 6.56:1, cleared the 4.5:1 floor, and was
    // therefore structurally invisible to this file until A30 pinned that one value exactly.
    // `every declared pairing matches its A31 exact-ratio pin` further down extends that same
    // treatment (assertEquals, +/-0.02, the form already used for `subtleText`/the disabled and
    // secondary exemptions below) to the entire declared set, not just the one token a real user
    // happened to report.

    @Test
    fun `every declared pairing clears its WCAG threshold`() {
        val failures = declaredColorPairings.mapNotNull { pairing ->
            // failsThreshold composites any declared alpha over the background first (A28 review,
            // Major 1) — checking pairing.foreground directly would silently re-introduce the
            // blind spot that let FindlyPermissionBanner's alpha-blended dismiss glyph ship.
            if (pairing.failsThreshold()) {
                val ratio = contrastRatio(pairing.effectiveForeground, pairing.background)
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

    // --- A31 (specs/003-android-client.md §4.1–§4.2, general form of A30): every declared pairing
    // now gets an exact-ratio pin too, not just the floor check above. Values below are computed
    // straight from LightFindlyColors/DarkFindlyColors via this file's own contrastRatio()/
    // compositeOver() (the same formula ContrastRatioReferenceTest pins against the published
    // #767676-on-#FFFFFF = 4.54:1 reference), never transcribed from HANDOFF.md or memory — that
    // transcription trap is exactly what produced A26's seven wrong numbers. Deliberately changing
    // a token now means updating its pin here in the same commit; that per-pin edit cost is the
    // point of A31, not a side effect to engineer around. ---

    @Test
    fun `every declared pairing matches its A31 exact-ratio pin, not just its WCAG floor`() {
        val expected: Map<String, Map<String, Double>> = mapOf(
            "onPrimary on primary" to mapOf("light" to 7.27, "dark" to 6.30),
            "onSurface on surface" to mapOf("light" to 16.54, "dark" to 16.17),
            "onSurface on surfaceVariant" to mapOf("light" to 14.60, "dark" to 14.13),
            "onDanger on danger" to mapOf("light" to 6.54, "dark" to 6.68),
            "subtleText on surface" to mapOf("light" to 9.08, "dark" to 7.43),
            "subtleText on surfaceVariant" to mapOf("light" to 8.01, "dark" to 6.49),
            "success used as text on surface" to mapOf("light" to 5.49, "dark" to 11.66),
            "warning used as text on surface (FindlyMapMarkerBubble stale age label)" to
                mapOf("light" to 5.39, "dark" to 12.06),
            "danger used as text on surface" to mapOf("light" to 5.95, "dark" to 6.88),
            "FindlyErrorState title (warning) on surfaceVariant" to mapOf("light" to 4.76, "dark" to 10.54),
            "FindlyPermissionBanner dismiss glyph (subtleText) on surfaceVariant" to
                mapOf("light" to 8.01, "dark" to 6.49),
            // NOTE: these two alpha-composited entries are NOT 7.19/8.45 despite that being what a
            // hand/idealized-double-precision calculation of "onSurface at 75% over surfaceVariant"
            // gives (and what this file's own pre-A31 doc comment claimed) — actually running it
            // through compositeOver()/Color(red:green:blue:) round-trips each channel through an
            // 8-bit sRGB pack, which visibly rounds 68.5/72.5/92.75-out-of-255 up to 69/73/93 before
            // the ratio is computed. Verified by printing compositeOver()'s actual output during
            // A31: this is the value the suite (and the app) really computes, so it is what gets
            // pinned — see the corrected comment on this pairing's declaration in
            // ColorTokenPairings.kt for the same fix applied to its doc comment.
            "FindlyPermissionBanner message (onSurface at 75%) on surfaceVariant" to
                mapOf("light" to 7.14, "dark" to 8.44),
            "PermissionDisclosureScreen closing text (onSurface at 75%) on surfaceVariant" to
                mapOf("light" to 7.14, "dark" to 8.44),
            "FindlyStatusChip Neutral (paused) label (onSurface) on surface" to
                mapOf("light" to 16.54, "dark" to 16.17),
            "outlineStrong vs surface" to mapOf("light" to 4.21, "dark" to 4.13),
            "outlineStrong vs surfaceVariant" to mapOf("light" to 3.71, "dark" to 3.61),
            "marker pill fill (markerOnlineDot) against primary" to mapOf("light" to 4.44, "dark" to 4.19),
            "paused-chip (FindlyStatusChip Neutral) border vs surface" to mapOf("light" to 4.21, "dark" to 4.13),
            "FindlyTopBar back chevron (primary) on surface" to mapOf("light" to 6.61, "dark" to 6.36),
            "FindlyTextField focused border (primary) vs surfaceVariant" to mapOf("light" to 5.84, "dark" to 5.56),
            "FindlyTextField error border (danger) vs surfaceVariant" to mapOf("light" to 5.25, "dark" to 6.02),
            "FindlyTextField error supporting text (danger) on surfaceVariant" to
                mapOf("light" to 5.25, "dark" to 6.02),
            "FindlyPermissionBanner severity stripe (danger) vs surfaceVariant" to
                mapOf("light" to 5.25, "dark" to 6.02),
            "FindlyPermissionBanner severity stripe (primary) vs surfaceVariant" to
                mapOf("light" to 5.84, "dark" to 5.56),
            "FindlyStatusChip Success label (onDanger) on fill (success)" to mapOf("light" to 6.03, "dark" to 11.32),
            "FindlyStatusChip Warning label (onDanger) on fill (warning)" to mapOf("light" to 5.93, "dark" to 11.71),
            "FindlyStatusChip Danger label (onDanger) on fill (danger)" to mapOf("light" to 6.54, "dark" to 6.68),
            "marker pill label (markerOnlineDotOn) on pill fill (markerOnlineDot)" to
                mapOf("light" to 10.07, "dark" to 7.69),
            "buttonPrimaryPressedFill vs onPrimary" to mapOf("light" to 9.80, "dark" to 4.96),
        )

        // Item 1 of A31's task description: an entry silently missing a pin is exactly the hole
        // this task exists to close, so it is asserted on explicitly rather than only surfacing as
        // "expected null" noise inside the mismatch loop below.
        val unpinned = declaredColorPairings.filter { expected[it.name] == null }
        assertTrue(
            "The following declared pairings have no A31 exact-ratio pin registered at all — add " +
                "one to `expected` above, it is not optional:\n" +
                unpinned.joinToString("\n") { "  [${it.theme}] ${it.name}" },
            unpinned.isEmpty(),
        )

        val mismatches = declaredColorPairings.mapNotNull { pairing ->
            val ratio = round2(contrastRatio(pairing.effectiveForeground, pairing.background))
            val expectedRatio = expected[pairing.name]?.get(pairing.theme)
            if (expectedRatio == null || Math.abs(ratio - expectedRatio) > 0.02) {
                "  [${pairing.theme}] ${pairing.name}: measured $ratio:1, pinned expectation $expectedRatio:1"
            } else {
                null
            }
        }

        assertTrue(
            "A declared pairing's contrast ratio drifted from its A31 exact pin " +
                "(specs/003-android-client.md §4.1–§4.2). Clearing the WCAG floor (the test above) is " +
                "not sufficient evidence a change was intentional or correct — that is the exact gap " +
                "that let A30 ship silently. If this is a deliberate token change, update the pinned " +
                "value here in the same commit; if it is not, this is a real regression:\n" +
                mismatches.joinToString("\n"),
            mismatches.isEmpty(),
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

    @Test
    fun `FindlyPermissionBanner dismiss glyph is not an alpha-blended onSurface literal — that failed light`() {
        // A28 review, Major 1 (security sweep): FindlyPermissionBanner.kt's dismiss "✕" used to
        // render `FindlyTheme.colors.onSurface.copy(alpha = 0.6f)` in `bodyLarge` (17sp/400, not
        // WCAG "large text") on the banner's `surfaceVariant` fill — a live, shipped pairing this
        // suite could not see at all, because every entry in declaredColorPairings assumed a solid
        // foreground. Blended and measured: light FAILS 4.5:1 (measured ~4.43:1); dark happens to
        // pass (~5.87:1). Fixed by using the `subtleText` token instead (see the declared
        // "FindlyPermissionBanner dismiss glyph (subtleText) on surfaceVariant" pairing) — this
        // pin exists so the old alpha-blended pattern can never quietly come back.
        val lightBlended = compositeOver(LightFindlyColors.onSurface, 0.6f, LightFindlyColors.surfaceVariant)
        val lightRatio = contrastRatio(lightBlended, LightFindlyColors.surfaceVariant)
        assertTrue(
            "light `onSurface` at 60% alpha, composited onto light `surfaceVariant`, measured " +
                "${round2(lightRatio)}:1 — expected it to stay BELOW 4.5:1 (this is the bug the fix " +
                "removed; if this now passes, alpha compositing itself is broken, not the banner).",
            lightRatio < TEXT_MIN_RATIO,
        )

        val darkBlended = compositeOver(DarkFindlyColors.onSurface, 0.6f, DarkFindlyColors.surfaceVariant)
        val darkRatio = contrastRatio(darkBlended, DarkFindlyColors.surfaceVariant)
        assertTrue(
            "dark `onSurface` at 60% alpha, composited onto dark `surfaceVariant`, measured " +
                "${round2(darkRatio)}:1 — expected this one to already clear 4.5:1 (the bug was " +
                "light-only, same shape as every other A26/A28 finding: a value that worked in one " +
                "theme and was never checked in the other).",
            darkRatio >= TEXT_MIN_RATIO,
        )
    }

    // --- A30 (specs/003-android-client.md §4.2 correction, filed 2026-08-06): a real-device
    // report called light-mode secondary text "barely readable". Investigation found this was NOT
    // a bug — pixel-sampled off an actual screenshot, the rendered color was exactly HANDOFF.md's
    // own specified `#4E5675` on `surface`, no alpha or Material3 default involved, measuring
    // 6.56:1 on `surface` / 5.79:1 on `surfaceVariant` — both already clear AA's 4.5:1 floor. The
    // design itself was the problem (low-chroma blue-grey at 13sp/400 subtitles / 12sp/700
    // uppercase headers): AA is a floor, not a target. `subtleText` light is darkened to `#3A4160`,
    // pinned below at 9.08:1 / 8.01:1. Dark `#98A1BD` is deliberately unchanged — it already
    // measures 7.43:1 / 6.49:1, materially better than light's original, which is likely why dark
    // never drew the complaint. This test is written to the NEW expected values while the token
    // still held the OLD `#4E5675` hex, so it went red first (matching this repo's strict TDD
    // convention) before ColorTokens.kt was updated to turn it green — see git log. ---

    @Test
    fun `light subtleText is A30's darkened value, not HANDOFFs original barely-readable one`() {
        val onSurfaceRatio = contrastRatio(LightFindlyColors.subtleText, LightFindlyColors.surface)
        assertEquals(
            "light `subtleText` on light `surface` expected 9.08:1 (A30's darkened `#3A4160` — up " +
                "from the original `#4E5675`'s 6.56:1, which already passed AA's 4.5:1 floor; this " +
                "pin is about the corrected design intent, not the pass/fail threshold, which " +
                "declaredColorPairings already covers). Got ${round2(onSurfaceRatio)}:1.",
            9.08,
            onSurfaceRatio,
            0.02,
        )

        val onSurfaceVariantRatio = contrastRatio(LightFindlyColors.subtleText, LightFindlyColors.surfaceVariant)
        assertEquals(
            "light `subtleText` on light `surfaceVariant` expected 8.01:1 (A30's darkened " +
                "`#3A4160` — up from the original `#4E5675`'s 5.79:1). Got " +
                "${round2(onSurfaceVariantRatio)}:1.",
            8.01,
            onSurfaceVariantRatio,
            0.02,
        )
    }

    @Test
    fun `dark subtleText is deliberately unchanged by A30 — already better than light's original`() {
        val onSurfaceRatio = contrastRatio(DarkFindlyColors.subtleText, DarkFindlyColors.surface)
        assertEquals(
            "dark `subtleText` (`#98A1BD`) on dark `surface` expected 7.43:1, unchanged by A30 — " +
                "already materially better than light's pre-A30 6.56:1, which is likely why dark " +
                "never drew the real-device complaint that prompted A30. Got " +
                "${round2(onSurfaceRatio)}:1.",
            7.43,
            onSurfaceRatio,
            0.02,
        )

        val onSurfaceVariantRatio = contrastRatio(DarkFindlyColors.subtleText, DarkFindlyColors.surfaceVariant)
        assertEquals(
            "dark `subtleText` (`#98A1BD`) on dark `surfaceVariant` expected 6.49:1, unchanged by " +
                "A30. Got ${round2(onSurfaceVariantRatio)}:1.",
            6.49,
            onSurfaceVariantRatio,
            0.02,
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

    // --- Disabled-control exemptions (A28 review, Minor 5 — cross-platform parity with iOS I29).
    // WCAG 2.1 explicitly exempts inactive/disabled UI components from its contrast success
    // criteria (1.4.3, 1.4.11) — a disabled button or field is not required to clear 4.5:1/3:1.
    // That is a reason to pin the measured value as a documented exemption, not a reason to leave
    // it untested: a silent change to a disabled-state color should still show up in a diff here,
    // exactly like the light-`outline` decorative exemption above. Values pinned to 2dp below. ---

    @Test
    fun `disabled-control pairings are documented WCAG-exempt pins, not pass-fail assertions`() {
        val expected = mapOf(
            "[disabled, exempt] ButtonDisabledLabel on surfaceVariant" to mapOf(
                "light" to 2.45,
                "dark" to 5.48,
            ),
            "[disabled, exempt] TextFieldDisabledText on TextFieldDisabledFill" to mapOf(
                "fixed (non-theme)" to 2.54,
            ),
            // A28 review round 2, outstanding item 2 (iOS parity): FindlyTextField.kt's `!enabled`
            // branch draws this as a real 1.5dp stroke; WCAG-exempt (disabled control), pinned so a
            // silent change still shows in a diff.
            "[disabled, exempt] TextFieldDisabledBorder on TextFieldDisabledFill" to mapOf(
                "fixed (non-theme)" to 1.19,
            ),
        )

        val mismatches = disabledControlExemptionPairings.mapNotNull { pairing ->
            val ratio = round2(contrastRatio(pairing.effectiveForeground, pairing.background))
            val expectedRatio = expected[pairing.name]?.get(pairing.theme)
            if (expectedRatio == null || Math.abs(ratio - expectedRatio) > 0.02) {
                "  [${pairing.theme}] ${pairing.name}: measured $ratio:1, pinned expectation " +
                    "$expectedRatio:1"
            } else {
                null
            }
        }

        assertTrue(
            "Disabled-control colors moved since this exemption was pinned (WCAG does not require " +
                "them to clear any threshold, but a silent change should still be visible here):\n" +
                mismatches.joinToString("\n"),
            mismatches.isEmpty(),
        )
    }

    // --- `secondary` (A28 addendum, cross-platform parity with iOS I29): documented-unrendered
    // exemption, not a pass/fail pairing — see secondaryUnrenderedExemptionPairings's doc comment
    // for why (it is genuinely unrendered on both platforms, and light measures BELOW 4.5:1
    // against HANDOFF.md's own claim of 4.6:1, so a real pairing here could never pass anyway).
    // A28 review round 2, outstanding item 3: extended to `surfaceVariant` too — at its current
    // value, `secondary` cannot carry text on EITHER light surface, not just `surface`. ---

    @Test
    fun `secondary is a documented not-yet-rendered exemption — light measures below 4point5 on both surfaces, contradicting HANDOFFmd`() {
        val expected = mapOf(
            "[unrendered, exempt] secondary on surface" to mapOf("light" to 4.45, "dark" to 12.04),
            "[unrendered, exempt] secondary on surfaceVariant" to mapOf("light" to 3.92, "dark" to 10.52),
        )

        val mismatches = secondaryUnrenderedExemptionPairings.mapNotNull { pairing ->
            val ratio = round2(contrastRatio(pairing.effectiveForeground, pairing.background))
            val expectedRatio = expected[pairing.name]?.get(pairing.theme)
            if (expectedRatio == null || Math.abs(ratio - expectedRatio) > 0.02) {
                "  [${pairing.theme}] ${pairing.name}: measured $ratio:1, pinned expectation " +
                    "$expectedRatio:1"
            } else {
                null
            }
        }

        assertTrue(
            "`secondary`'s measured contrast against `surface`/`surfaceVariant` moved since this " +
                "exemption was pinned. If light now clears 4.5:1 on both, HANDOFF.md's claimed " +
                "4.6:1 may finally be accurate again — that's fine, this pin just needs updating, " +
                "it does not automatically mean `secondary` may now be declared as a real pairing " +
                "(it must still actually be rendered somewhere first):\n" + mismatches.joinToString("\n"),
            mismatches.isEmpty(),
        )
    }

    // --- Permanent proof the detection mechanism itself works (A28 addendum, iOS I29 review
    // parity) — not a one-off manual check, live in the suite for every future reader. ---

    @Test
    fun `the failure-detection mechanism actually flags a failing pairing — synthetic proof`() {
        // Inverted expectation: this assertion only PASSES because failsThreshold() correctly
        // scores an impossible-to-clear pairing (black on black, 1:1) as a failure. If
        // failsThreshold()'s comparison direction, threshold wiring, or effectiveForeground
        // resolution ever breaks such that this synthetic pairing stops being detected as failing,
        // this test goes red — which is the point: it proves declaredColorPairings' silence means
        // "nothing failed", not "the check never ran".
        assertTrue(
            "black-on-black (1:1) must be detected as failing a ${TEXT_MIN_RATIO}:1 threshold — if " +
                "this is false, the failure-detection mechanism itself is broken, and a real AA " +
                "failure could pass declaredColorPairings silently.",
            syntheticAlwaysFailingPairing.failsThreshold(),
        )
    }

    private fun round2(value: Double): Double = round(value * 100) / 100
}
