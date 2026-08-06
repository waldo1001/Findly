package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The color half of the design-token contract (specs/003-android-client.md §4.1/§4.2).
 * These are the ONLY color values allowed to exist anywhere in the app outside this file —
 * every component reads [com.findly.android.ui.designsystem.FindlyTheme.colors] instead of
 * constructing a [Color] literal.
 *
 * The 11 fields above the divider are the normative §4.1 vocabulary (do not rename without a
 * spec PR). The fields below it are additive, theme-resolved helper values the 2a "Ember / Dusk"
 * handoff (design/findly-design-system/2a-ember-dusk/HANDOFF.md) needs but that don't belong in
 * the 11-role contract itself — kept on this same per-theme data class (rather than as bare
 * top-level constants, as the handoff's own ready-to-paste `FindlyColors.kt` does) so they
 * resolve automatically with the active theme through the existing [LocalFindlyColors]
 * composition local, the same way every contract color already does. Most translucent tints the
 * handoff derives from `primary` (focus rings, the textfield focus ring, the geofence circle
 * fill) are computed at the call site as `primary.copy(alpha = …)` instead of being pinned here
 * as a light-only literal — that keeps them correct in dark automatically, since the handoff only
 * ever specifies these as an alpha over the light `primary` hex, which is `primary` itself. A few
 * fields below (`buttonPrimaryShadowTint`, `buttonPrimaryPressedFill`, `markerOnlineDot`/
 * `markerOnlineDotOn`, `outlineStrong`) are NOT alpha-derivable this way — either the handoff (or
 * measurement — see their individual docs) requires an opaque, non-alpha color that genuinely
 * differs between themes, so those are explicit per-theme fields instead.
 */
@Immutable
data class FindlyColorTokens(
    val primary: Color,
    val onPrimary: Color,
    val secondary: Color,
    val surface: Color,
    val onSurface: Color,
    val surfaceVariant: Color,
    val danger: Color,
    val onDanger: Color,
    val success: Color,
    val warning: Color,
    val outline: Color,
    // --- Additive, non-contract helpers (2a handoff) ---
    /**
     * Strokes that carry meaning (an unselected control border, a focus ring, an input outline)
     * MUST use this instead of [outline]. Light [outline] is only 2.1:1 — legal for decorative
     * hairlines and dividers only.
     *
     * **Corrected post-A26 security review (measured, not HANDOFF.md's claim):** HANDOFF.md and
     * the original specs/003 §4.2 text asserted "in dark, `outline` itself clears 3:1 and serves
     * both" — measured, dark `outline` `#3A4463` is only **1.99:1** on `surface` `#0B0F1C` and
     * **1.74:1** on `surfaceVariant` `#161D33`, i.e. it does NOT clear 3:1. `outlineStrong` in
     * dark is therefore its own value, `#6B739A` (the same hex light already uses) —
     * **4.13:1 on dark `surface`, 3.61:1 on dark `surfaceVariant`**, both AA-for-UI-components
     * (>=3:1). Decorative [outline] itself is unaffected by this fix and stays as specified.
     */
    val outlineStrong: Color,
    /** The dot inside a `primary` [com.findly.android.ui.designsystem.components.FindlyMapMarkerBubble]
     * bubble's "NOW" pill fill.
     *
     * **Corrected post-A26 security review (measured, not HANDOFF.md's claim):** HANDOFF.md
     * asserted `#52E39B` "in BOTH themes ... 5.4:1 on #3A46C8" — that citation is itself against
     * *light* `primary` only (measured **4.44:1**, close enough to still pass, the 5.4 figure was
     * simply wrong) and was never checked against *dark* `primary` `#7C8BFF`, where `#52E39B`
     * measures **1.83:1** and disappears. Dark now uses its own fill, `#0B3B26` — **4.19:1** on
     * dark `primary` — with [markerOnlineDotOn] inverted to `#52E39B` as the label color on top of
     * it (**7.69:1**, comfortably AA). Light is unchanged (`#52E39B` fill / `#062418` label). Never
     * light-theme [success] as the fill — that measures 1.2:1 there and disappears (this part of
     * HANDOFF.md's rule 2 was correct). */
    val markerOnlineDot: Color,
    /** Text color on top of [markerOnlineDot] — see that field's doc for the per-theme values and
     * measured contrast. */
    val markerOnlineDotOn: Color,
    /** [onSurface] at ~70% — used for muted/secondary text (e.g. `FindlyListRow` subtitles).
     * HANDOFF.md gives exact hex per theme rather than a computed alpha. */
    val subtleText: Color,
    /** Neutral-black shadow opacity for `FindlyTheme.elevation.level1/2/3` (HANDOFF.md's
     * elevation table: `{blur, y, opacity light|dark}`). Shadows stay neutral black in both
     * themes — never tinted — except `FindlyButton`'s primary variant, which uses
     * [buttonPrimaryShadowTint] instead. */
    val shadowLevel1Alpha: Float,
    val shadowLevel2Alpha: Float,
    val shadowLevel3Alpha: Float,
    /**
     * `FindlyButton` primary's `level2` shadow tint — `primary` at 35% alpha in light
     * (HANDOFF.md: "level2 shadow tinted rgba(58,70,200,.35) on light"), a plain neutral black
     * shadow (at [shadowLevel2Alpha]) in dark, where the handoff specifies no tint.
     *
     * **A26 code-review fix (Minor 6):** this used to be resolved at the `FindlyButton` call site
     * via a raw `isDark: Boolean` flag on this class. That flag was removed — a bare theme
     * boolean sitting among otherwise fully-resolved semantic colours is exactly the kind of
     * escape hatch that invites a future call site to branch on `isDark` directly instead of
     * reaching for a token. This field is `FindlyButton`'s only remaining call site; it stays a
     * semantic, self-resolving color like every other field on this class, with no theme
     * conditional left anywhere outside this file.
     */
    val buttonPrimaryShadowTint: Color,
    /**
     * `FindlyButton` primary's pressed fill (A26 code-review fix, Minor 7 — HANDOFF.md specifies
     * this explicitly ("Pressed: fill `#2C36A0`") and it was originally left unwired, relying on
     * the platform ripple alone; the ripple is still layered on top, but the fill itself is now
     * implemented too).
     *
     * Light is the handoff's own literal `#2C36A0` — a ~22% darken of light `primary` toward
     * black, verified well clear of 4.5:1 for `onPrimary` white on top of it. Dark is **not** the
     * same literal (HANDOFF.md gives only one hex, implicitly light-only, the same gap as the two
     * Major contrast findings above) — applying it as a fixed overlay in dark would sit `onPrimary`
     * `#0A0F27` (near-black) at only **1.93:1** on the resulting fill (measured, corrected in A26
     * re-review — an earlier draft of this comment said "~4.0:1", which was wrong), which fails
     * normal-text AA (the button label is 16sp/600, under WCAG's 14pt-bold "large text"
     * threshold). Dark instead uses a shallower ~12% darken of dark `primary` toward black,
     * `#6D7AE0`, keeping `onPrimary` at **4.96:1** on it.
     */
    val buttonPrimaryPressedFill: Color,
)

/**
 * Design 2a — "Ember / Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md).
 * Ember layout/type/spacing/shape; Dusk indigo/cyan color values. Every text/essential-icon
 * pairing meets WCAG 2.1 AA (ratios in HANDOFF.md). Fully swappable via this seam.
 */
val LightFindlyColors = FindlyColorTokens(
    primary = Color(0xFF3A46C8),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF0E7C8F),
    surface = Color(0xFFF2F4FB),
    onSurface = Color(0xFF10142A),
    surfaceVariant = Color(0xFFE2E6F5),
    danger = Color(0xFFB3261E),
    onDanger = Color(0xFFFFFFFF),
    success = Color(0xFF10714A),
    warning = Color(0xFF8A5A00),
    outline = Color(0xFFA9B0CE),
    outlineStrong = Color(0xFF6B739A),
    markerOnlineDot = Color(0xFF52E39B),
    markerOnlineDotOn = Color(0xFF062418),
    subtleText = Color(0xFF4E5675),
    shadowLevel1Alpha = 0.10f,
    shadowLevel2Alpha = 0.14f,
    shadowLevel3Alpha = 0.18f,
    buttonPrimaryShadowTint = Color(0xFF3A46C8).copy(alpha = 0.35f),
    // HANDOFF.md's own literal ("Pressed: fill #2C36A0") — onPrimary white on it is comfortably
    // >4.5:1 (well above the already-verified 7.3:1 onPrimary-on-primary pairing this darkens).
    buttonPrimaryPressedFill = Color(0xFF2C36A0),
)

val DarkFindlyColors = FindlyColorTokens(
    primary = Color(0xFF7C8BFF),
    onPrimary = Color(0xFF0A0F27),
    secondary = Color(0xFF4FE3D0),
    surface = Color(0xFF0B0F1C),
    onSurface = Color(0xFFE8ECF7),
    surfaceVariant = Color(0xFF161D33),
    danger = Color(0xFFFF6B6B),
    onDanger = Color(0xFF2A0708),
    success = Color(0xFF52E39B),
    warning = Color(0xFFFFC44D),
    outline = Color(0xFF3A4463),
    // A26 security-review fix: was aliased to dark `outline` (#3A4463), measured only 1.99:1 on
    // surface / 1.74:1 on surfaceVariant — not the "clears 3:1" HANDOFF.md/§4.2 claimed. #6B739A
    // (light's own outlineStrong value) measures 4.13:1 / 3.61:1 here instead.
    outlineStrong = Color(0xFF6B739A),
    // A26 security-review fix: was #52E39B (same as light), which measures only 1.83:1 on dark
    // `primary` #7C8BFF and disappears. #0B3B26 measures 4.19:1 on dark `primary`; label inverts
    // to #52E39B on top of it (7.69:1).
    markerOnlineDot = Color(0xFF0B3B26),
    markerOnlineDotOn = Color(0xFF52E39B),
    subtleText = Color(0xFF98A1BD),
    shadowLevel1Alpha = 0.30f,
    shadowLevel2Alpha = 0.45f,
    shadowLevel3Alpha = 0.60f,
    // Dark gets no tint per HANDOFF.md — a plain neutral shadow at the normal level2 alpha.
    buttonPrimaryShadowTint = Color.Black.copy(alpha = 0.45f),
    // A26 code-review fix (Minor 7): HANDOFF.md gives only the light pressed-fill hex (#2C36A0),
    // which would put dark `onPrimary` #0A0F27 (near-black) at 1.93:1 on it (measured, corrected
    // in re-review from an earlier, wrong "~4.0:1") — below 4.5:1 for the 16sp/600 button label
    // (not "large text" under WCAG's 14pt-bold threshold). A shallower ~12% darken of dark
    // `primary` toward black keeps `onPrimary` at a measured 4.96:1 instead.
    buttonPrimaryPressedFill = Color(0xFF6D7AE0),
)

/** `FindlyButton` disabled label color, both themes (HANDOFF.md: "Disabled: fill surfaceVariant,
 * label `#8D93AB`") — a fixed value the handoff gives once, not per-theme. */
val ButtonDisabledLabel = Color(0xFF8D93AB)

/** `FindlyTextField` disabled treatment (HANDOFF.md: "Disabled: fill `#E8EAF2`, border `#D3D7E6`,
 * text `#8D93AB`") — fixed values, not theme-resolved (the mocks only specify one disabled
 * treatment, not a light/dark pair). */
val TextFieldDisabledFill = Color(0xFFE8EAF2)
val TextFieldDisabledBorder = Color(0xFFD3D7E6)
val TextFieldDisabledText = Color(0xFF8D93AB)

/** `FindlySwitchRow`'s native M3 switch thumb — literally "white thumb" in both themes/states per
 * HANDOFF.md (`FindlySwitchRow`: "on = `primary` track, off = `outline` track, white thumb"),
 * not derived from any theme token. */
val SwitchThumbColor = Color(0xFFFFFFFF)

val LocalFindlyColors = staticCompositionLocalOf { LightFindlyColors }
