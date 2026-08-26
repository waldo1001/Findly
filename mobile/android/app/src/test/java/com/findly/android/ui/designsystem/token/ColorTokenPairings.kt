package com.findly.android.ui.designsystem.token

import androidx.compose.ui.graphics.Color

/** WCAG 2.1 minimum for body text (specs/003-android-client.md §4.2, A28 filing). */
const val TEXT_MIN_RATIO = 4.5

/** WCAG 2.1 minimum for meaningful strokes/graphical objects and component-level fills (A28
 * filing) — large text also qualifies at this threshold, but nothing declared here relies on the
 * large-text exception; every text pairing below is held to [TEXT_MIN_RATIO] instead. */
const val GRAPHICAL_MIN_RATIO = 3.0

/**
 * One declared token pairing this app relies on for accessibility, resolved for one theme. Add a
 * new pairing here — not new test code — when a new token combination ships (A28,
 * specs/003-android-client.md §4.1–§4.2: "Encode the pairings as data, so adding a token pairing
 * is a data edit, not new test code").
 *
 * [foregroundAlpha] (A28 review, Major 1) defaults to fully opaque. When a component renders
 * `token.copy(alpha = x)` instead of a solid token — as `FindlyPermissionBanner`'s dismiss glyph
 * did before this review — that alpha MUST be captured here too, via [effectiveForeground]
 * ([compositeOver]-ing the foreground onto the background before the ratio is computed) —
 * otherwise the declared pairing is checking a color the app never actually draws.
 */
data class ColorPairing(
    val name: String,
    val theme: String,
    val threshold: Double,
    val foreground: Color,
    val background: Color,
    val foregroundAlpha: Float = 1f,
)

/** The color actually reaching the screen for [this] pairing — composited over [background] when
 * [ColorPairing.foregroundAlpha] is translucent, otherwise the solid foreground unchanged. Every
 * contrast assertion in this suite must use this, never [ColorPairing.foreground] directly. */
val ColorPairing.effectiveForeground: Color
    get() = if (foregroundAlpha >= 1f) foreground else compositeOver(foreground, foregroundAlpha, background)

/** `true` iff [this] pairing does NOT clear its own [ColorPairing.threshold] — the exact check
 * [declaredColorPairings] is asserted against in [ColorTokenContrastTest]. Factored out (A28
 * addendum, iOS I29 review parity) so the synthetic always-failing proof pairing exercises the
 * real detection logic, not just [contrastRatio] in isolation (already covered by
 * [ContrastRatioReferenceTest]). */
fun ColorPairing.failsThreshold(): Boolean = contrastRatio(effectiveForeground, background) < threshold

private fun textPairing(name: String, theme: String, fg: Color, bg: Color, fgAlpha: Float = 1f) =
    ColorPairing(name, theme, TEXT_MIN_RATIO, fg, bg, fgAlpha)

private fun graphicalPairing(name: String, theme: String, fg: Color, bg: Color, fgAlpha: Float = 1f) =
    ColorPairing(name, theme, GRAPHICAL_MIN_RATIO, fg, bg, fgAlpha)

/**
 * Every pairing A28 (specs/003-android-client.md §4.1–§4.2) requires to clear its WCAG 2.1
 * threshold, in both themes. [ColorTokenContrastTest] asserts every entry here passes; the four
 * pairings that were measured to actually FAIL against the design handoff's own claims (dark
 * `outline`, the old dark marker-pill fill, a literal white on dark `success`, and HANDOFF's
 * light-only `buttonPrimaryPressedFill` literal in dark) are pinned as their own explicit,
 * separately-named tests in [ColorTokenContrastTest] instead of being listed here — this table is
 * exclusively the "must always pass" contract. The pre-fix `FindlyPermissionBanner` alpha-blended
 * dismiss glyph is pinned the same way, alongside the fixed pairing this table declares instead.
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
        // FindlyMapMarkerBubble.kt's StaleBubble renders "▲ $ageText" in `warning` directly on the
        // bubble's own `surface` fill — this is the genuine render site for warning-as-text-on-
        // surface (A28 review, Major 2 follow-up: verified, not assumed).
        add(textPairing("warning used as text on surface (FindlyMapMarkerBubble stale age label)", theme, colors.warning, colors.surface))
        add(textPairing("danger used as text on surface", theme, colors.danger, colors.surface))
        // `secondary` is deliberately NOT declared here — see [secondaryUnrenderedExemptionPairings]
        // below (A28 addendum: verified unrendered on both platforms, and asserting a pairing here
        // would be inventing a combination nothing draws — plus it would be a pairing this suite
        // could never pass, see that val's comment).

        // A28 review, Major 2: FindlyErrorState.kt renders its title in `warning` on the
        // component's own fill, `surfaceVariant` — a different, more forgiving background than
        // "warning on surface" above. Declared against the background actually rendered so a
        // future tweak to `warning`/`surfaceVariant` can't silently drop the real UI below AA
        // while the suite stays green on a number nothing ships.
        add(textPairing("FindlyErrorState title (warning) on surfaceVariant", theme, colors.warning, colors.surfaceVariant))

        // A28 review, Major 1: FindlyPermissionBanner.kt's dismiss "✕" — post-fix, renders
        // `subtleText` (not an ad-hoc `onSurface.copy(alpha = 0.6f)`) on the banner's own
        // `surfaceVariant` fill. Numerically identical to "subtleText on surfaceVariant" above;
        // named separately because the review specifically flagged this render site.
        add(textPairing("FindlyPermissionBanner dismiss glyph (subtleText) on surfaceVariant", theme, colors.subtleText, colors.surfaceVariant))

        // A28 review round 2 (interrupted-round outstanding item 1): FindlyPermissionBanner.kt:81
        // renders its message body as `onSurface.copy(alpha = 0.75f)` on the banner's own
        // `surfaceVariant` fill — a different, still-live alpha blend six lines from the dismiss
        // glyph above that was structurally invisible to this suite until now. Unlike the dismiss
        // glyph, this one was never wrong: composited, it measures 7.14:1 light / 8.44:1 dark
        // (computed from LightFindlyColors/DarkFindlyColors via the same relativeLuminance/
        // contrastRatio formula this file's tests are pinned against — see ContrastRatioReferenceTest;
        // corrected by A31 from an earlier "7.19/8.45" claimed here, which was a hand/idealized
        // calculation that skipped compositeOver()'s real behavior — reconstructing a `Color` from
        // its blended float components round-trips through an 8-bit sRGB pack, which measurably
        // rounds the blended channels before the ratio is computed. See A31's pinned exact value on
        // this pairing in ColorTokenContrastTest.kt for how this was caught),
        // comfortably clearing 4.5:1 in both themes. Declared via [foregroundAlpha] so a future
        // change to `onSurface`, `surfaceVariant`, or the 0.75 alpha itself cannot silently drop
        // below AA without this suite catching it — do not change the component's color to "fix"
        // this entry, it already passes.
        add(textPairing("FindlyPermissionBanner message (onSurface at 75%) on surfaceVariant", theme, colors.onSurface, colors.surfaceVariant, fgAlpha = 0.75f))

        // A28 review round 2 (interrupted-round outstanding item 4): PermissionDisclosureScreen.kt:88
        // renders its closing paragraph with the identical `onSurface.copy(alpha = 0.75f)` on
        // `surfaceVariant` pattern as the banner message above — same tokens, same alpha, so
        // numerically identical (7.14:1 light / 8.44:1 dark — see the correction note on the
        // pairing above), but declared as its own entry because
        // it is a distinct render site in a screen file. Declaring a pairing here is scope-appropriate
        // for A28 (it is a test/doc addition over an existing token combination, not a screen redesign
        // — that is A27) and does not restyle the screen.
        add(textPairing("PermissionDisclosureScreen closing text (onSurface at 75%) on surfaceVariant", theme, colors.onSurface, colors.surfaceVariant, fgAlpha = 0.75f))

        // A28 review, Minor 5 (cross-platform parity with iOS I29): FindlyStatusChip's
        // Neutral/paused tone renders its `onSurface` label directly on whatever `surface` it's
        // placed on (HomeScreen's member list, per HANDOFF.md). Numerically identical to
        // "onSurface on surface" above; named separately for the same parity reason iOS asserts it
        // by name.
        add(textPairing("FindlyStatusChip Neutral (paused) label (onSurface) on surface", theme, colors.onSurface, colors.surface))

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

        // A28 review, Minor 3 — five previously-uncovered rendered pairings:
        // FindlyTopBar.kt's back chevron ("‹") is a navigation icon, not body text — a
        // meaning-carrying graphical object, held to 3:1 like a stroke.
        add(graphicalPairing("FindlyTopBar back chevron (primary) on surface", theme, colors.primary, colors.surface))
        // FindlyTextField.kt's focused state swaps the field border to `primary` on the field's
        // `surfaceVariant` fill (the translucent focus *ring* on top of it is a separate, already
        // alpha-derived-from-primary overlay, not this border).
        add(graphicalPairing("FindlyTextField focused border (primary) vs surfaceVariant", theme, colors.primary, colors.surfaceVariant))
        // FindlyTextField.kt's error state: the border is a stroke (3:1); the "✕ $supportingText"
        // message below it is real text (4.5:1). Both are `danger` on the same `surfaceVariant`
        // fill, so the two entries share a color pair but not a threshold.
        add(graphicalPairing("FindlyTextField error border (danger) vs surfaceVariant", theme, colors.danger, colors.surfaceVariant))
        add(textPairing("FindlyTextField error supporting text (danger) on surfaceVariant", theme, colors.danger, colors.surfaceVariant))
        // FindlyPermissionBanner.kt's severity stripe: a solid 4dp bar in `danger` (CANNOT_REPORT)
        // or `primary` (FOREGROUND_ONLY) against the banner's `surfaceVariant` fill — a meaningful
        // state indicator (which severity this is), not decoration, so 3:1 applies.
        add(graphicalPairing("FindlyPermissionBanner severity stripe (danger) vs surfaceVariant", theme, colors.danger, colors.surfaceVariant))
        add(graphicalPairing("FindlyPermissionBanner severity stripe (primary) vs surfaceVariant", theme, colors.primary, colors.surfaceVariant))

        // --- Component-level pairs, 4.5:1 (label text on its own fill) ---
        add(textPairing("FindlyStatusChip Success label (onDanger) on fill (success)", theme, colors.onDanger, colors.success))
        add(textPairing("FindlyStatusChip Warning label (onDanger) on fill (warning)", theme, colors.onDanger, colors.warning))
        add(textPairing("FindlyStatusChip Danger label (onDanger) on fill (danger)", theme, colors.onDanger, colors.danger))
        add(textPairing("marker pill label (markerOnlineDotOn) on pill fill (markerOnlineDot)", theme, colors.markerOnlineDotOn, colors.markerOnlineDot))
        add(textPairing("buttonPrimaryPressedFill vs onPrimary", theme, colors.onPrimary, colors.buttonPrimaryPressedFill))
    }
}

/**
 * Disabled-control pairings (A28 review, Minor 5, cross-platform parity with iOS I29). WCAG 2.1's
 * contrast success criteria (1.4.3, 1.4.11) explicitly exempt inactive/disabled user-interface
 * components — a disabled `FindlyButton`/`FindlyTextField` is not required to clear 4.5:1 or
 * 3:1 — but that is a reason to pin the *measured* value as a documented exemption, not a reason
 * to leave it untested: a silent change to a disabled-state color should still be visible in a
 * diff, exactly like the light-`outline` decorative exemption below is. Not included in
 * [declaredColorPairings] because these are not required to pass; [ColorTokenContrastTest] asserts
 * their pinned values directly instead.
 */
val disabledControlExemptionPairings: List<ColorPairing> = buildList {
    for ((theme, colors) in listOf("light" to LightFindlyColors, "dark" to DarkFindlyColors)) {
        // FindlyButton.kt: disabled fill is theme `surfaceVariant`; label is the fixed (non-theme)
        // ButtonDisabledLabel (#8D93AB) HANDOFF.md gives once, not per-theme.
        add(textPairing("[disabled, exempt] ButtonDisabledLabel on surfaceVariant", theme, ButtonDisabledLabel, colors.surfaceVariant))
    }
    // FindlyTextField.kt: disabled fill/text are both the fixed (non-theme) HANDOFF.md palette —
    // one pairing, not per-theme, since neither side varies with the active theme.
    add(textPairing("[disabled, exempt] TextFieldDisabledText on TextFieldDisabledFill", "fixed (non-theme)", TextFieldDisabledText, TextFieldDisabledFill))
    // A28 review round 2 (interrupted-round outstanding item 2, cross-platform parity — iOS already
    // pins this): FindlyTextField.kt's `!enabled` branch draws TextFieldDisabledBorder as a real
    // 1.5dp stroke around TextFieldDisabledFill, not a decorative artifact — it had no coverage at
    // all before this pin. Measured 1.19:1, well under the 3:1 a meaning-carrying stroke would need,
    // but WCAG 2.1 (1.4.3, 1.4.11) exempts disabled controls from its contrast criteria entirely, so
    // this is a documented exemption like the others in this list, not a failure. Graphical (border),
    // not text, hence [graphicalPairing] — the threshold field is unused by the exemption test below,
    // which pins the exact measured value instead of asserting pass/fail.
    add(graphicalPairing("[disabled, exempt] TextFieldDisabledBorder on TextFieldDisabledFill", "fixed (non-theme)", TextFieldDisabledBorder, TextFieldDisabledFill))
}

/**
 * `secondary` (A28 addendum, cross-platform parity with iOS I29) is one of the 11 normative §4.1
 * contract colors, but is genuinely unrendered on **both** platforms today — grep-verified here
 * (no `colors.secondary`/`tokens.secondary` call site outside `FindlyTheme.kt`'s own
 * `ColorScheme(secondary = ...)` mapping), and independently verified on iOS by that platform's
 * code reviewer (`FindlyButtonStyleKind.secondary` is only an enum case name; the actual rendering
 * uses `onSurface`/`outlineStrong`/`Color.clear`). A [declaredColorPairings] entry would be
 * inventing a combination nothing draws — and, worse, it would be an entry this suite could never
 * pass: HANDOFF.md claims light `secondary` on light `surface` is 4.6:1, but measured reality is
 * **4.45:1**, already below the 4.5:1 text floor (dark is fine at 12.04:1) — the same "HANDOFF's
 * own contrast column is wrong" class of bug A26 found seven times, just never yet shipped because
 * nothing renders this pairing.
 *
 * **Plainly: at its current value, `secondary` cannot carry text on either light surface.**
 * `surfaceVariant` is worse than `surface`, not better — measured **3.92:1** in light (vs. `surface`'s
 * 4.45:1), still comfortably clear in dark at **10.52:1** (vs. `surface`'s 12.04:1). Both light
 * surfaces are pinned here for exactly that reason: this is not a one-surface fluke, it is the color
 * itself.
 *
 * Pinned here instead, the same shape as the disabled-control exemptions above, so a token change
 * still shows in a diff. **Whoever first wires `secondary` into a real component MUST add a real
 * [declaredColorPairings] entry for whatever it's actually rendered against at that time** — and
 * per the note above, that will very likely mean `secondary` cannot go directly on `surface` OR
 * `surfaceVariant` in light without a token change first.
 */
val secondaryUnrenderedExemptionPairings: List<ColorPairing> = listOf(
    textPairing("[unrendered, exempt] secondary on surface", "light", LightFindlyColors.secondary, LightFindlyColors.surface),
    textPairing("[unrendered, exempt] secondary on surface", "dark", DarkFindlyColors.secondary, DarkFindlyColors.surface),
    textPairing("[unrendered, exempt] secondary on surfaceVariant", "light", LightFindlyColors.secondary, LightFindlyColors.surfaceVariant),
    textPairing("[unrendered, exempt] secondary on surfaceVariant", "dark", DarkFindlyColors.secondary, DarkFindlyColors.surfaceVariant),
)

/**
 * A synthetic pairing that can never pass (A28 addendum, iOS I29 review parity) — permanent, live
 * proof that [ColorPairing.failsThreshold] (the exact check [declaredColorPairings] is asserted
 * against) actually detects a failure, rather than relying on a one-off manual "temporarily force
 * a bad value" check that only ever lived in a review report. [ColorTokenContrastTest] asserts
 * this pairing's [ColorPairing.failsThreshold] is `true` — an inverted expectation that only passes
 * *because* the detection mechanism correctly scores it as failing.
 */
val syntheticAlwaysFailingPairing = ColorPairing(
    name = "[synthetic, proof-only] black on black — must never pass",
    theme = "n/a",
    threshold = TEXT_MIN_RATIO,
    foreground = Color(0xFF000000),
    background = Color(0xFF000000),
)
