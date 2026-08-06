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
 * composition local, the same way every contract color already does. Any translucent tint the
 * handoff derives from `primary` (focus rings, the textfield focus ring, the button shadow tint,
 * the geofence circle fill) is computed at the call site as `primary.copy(alpha = …)` instead of
 * being pinned here as a light-only literal — that keeps it correct in dark automatically, since
 * the handoff itself only ever specifies these as an alpha over the light `primary` hex, which is
 * `primary` itself.
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
     * hairlines and dividers only. In dark, [outline] itself already clears 3:1, so this equals
     * [outline] there (HANDOFF.md "Two rules that must survive review", rule 1).
     */
    val outlineStrong: Color,
    /** The dot inside a `primary` [com.findly.android.ui.designsystem.components.FindlyMapMarkerBubble]
     * bubble's "NOW" pill — `#52E39B` in BOTH themes (5.4:1 on `#3A46C8`). Never light-theme
     * [success] there (measures 1.2:1 and disappears — HANDOFF.md rule 2). */
    val markerOnlineDot: Color,
    /** Text color on top of [markerOnlineDot]. */
    val markerOnlineDotOn: Color,
    /** [onSurface] at ~70% — used for muted/secondary text (e.g. `FindlyListRow` subtitles).
     * HANDOFF.md gives exact hex per theme rather than a computed alpha. */
    val subtleText: Color,
    /** Neutral-black shadow opacity for `FindlyTheme.elevation.level1/2/3` (HANDOFF.md's
     * elevation table: `{blur, y, opacity light|dark}`). Shadows stay neutral black in both
     * themes — never tinted — except `FindlyButton`'s primary variant, which tints its `level2`
     * shadow with `primary` on light only (see [isDark] / that component). */
    val shadowLevel1Alpha: Float,
    val shadowLevel2Alpha: Float,
    val shadowLevel3Alpha: Float,
    /** True for [DarkFindlyColors]. The one thing HANDOFF.md specifies as a *light-only*
     * exception (`FindlyButton` primary's tinted shadow) needs to know which theme is active;
     * every other value above already resolves per-theme without a branch. */
    val isDark: Boolean,
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
    isDark = false,
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
    outlineStrong = Color(0xFF3A4463),
    markerOnlineDot = Color(0xFF52E39B),
    markerOnlineDotOn = Color(0xFF062418),
    subtleText = Color(0xFF98A1BD),
    shadowLevel1Alpha = 0.30f,
    shadowLevel2Alpha = 0.45f,
    shadowLevel3Alpha = 0.60f,
    isDark = true,
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
