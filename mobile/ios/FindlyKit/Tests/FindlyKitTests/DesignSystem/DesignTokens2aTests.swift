import SwiftUI
import Testing
@testable import FindlyKit

/// design/findly-design-system/2a-ember-dusk/HANDOFF.md — direction 2a "Ember / Dusk", the
/// versioned token contract picked for both mobile clients (specs/003 §4.2, specs/004 §2.1).
/// These pin the exact values the handoff calls "final and exact" so a future edit can't drift
/// from the handoff without a red test. Values only — token *names* are unchanged (I27).
struct DesignTokens2aTests {

    // MARK: - Colors — light

    @Test func lightColors_matchHandoffHexValues() {
        let c = ColorTokens.light
        #expect(c.primary == Color(hex: 0x3A46C8))
        #expect(c.onPrimary == Color(hex: 0xFFFFFF))
        #expect(c.secondary == Color(hex: 0x0E7C8F))
        #expect(c.surface == Color(hex: 0xF2F4FB))
        #expect(c.onSurface == Color(hex: 0x10142A))
        #expect(c.surfaceVariant == Color(hex: 0xE2E6F5))
        #expect(c.danger == Color(hex: 0xB3261E))
        #expect(c.onDanger == Color(hex: 0xFFFFFF))
        #expect(c.success == Color(hex: 0x10714A))
        #expect(c.warning == Color(hex: 0x8A5A00))
        #expect(c.outline == Color(hex: 0xA9B0CE))
    }

    // MARK: - Colors — dark

    @Test func darkColors_matchHandoffHexValues() {
        let c = ColorTokens.dark
        #expect(c.primary == Color(hex: 0x7C8BFF))
        #expect(c.onPrimary == Color(hex: 0x0A0F27))
        #expect(c.secondary == Color(hex: 0x4FE3D0))
        #expect(c.surface == Color(hex: 0x0B0F1C))
        #expect(c.onSurface == Color(hex: 0xE8ECF7))
        #expect(c.surfaceVariant == Color(hex: 0x161D33))
        #expect(c.danger == Color(hex: 0xFF6B6B))
        #expect(c.onDanger == Color(hex: 0x2A0708))
        #expect(c.success == Color(hex: 0x52E39B))
        #expect(c.warning == Color(hex: 0xFFC44D))
        #expect(c.outline == Color(hex: 0x3A4463))
    }

    // MARK: - The two contrast traps the handoff calls out by name

    // Light `outline` (#A9B0CE) is decorative-only (measured 1.95:1 vs `surface` — the handoff's
    // "2.1:1" was slightly overstated; no threshold applies to it either way, it's hairline-only).
    // Any stroke that carries meaning must use this stronger, theme-invariant color instead —
    // measured 4.21:1 vs light `surface` / 3.71:1 vs `surfaceVariant`, and 4.13:1 / 3.61:1 in dark
    // (the handoff's "3.4:1" for this color was understated in the other direction).
    @Test func findlyOutlineStrong_isTheHandoffValue_andDistinctFromDecorativeOutline() {
        #expect(Color.findlyOutlineStrong == Color(hex: 0x6B739A))
        #expect(Color.findlyOutlineStrong != ColorTokens.light.outline)
    }

    // The dot inside a `primary` marker bubble is #52E39B in BOTH themes (5.4:1 on #3A46C8).
    // Light-theme `success` (#10714A) measures 1.2:1 there and must never be substituted in.
    @Test func findlyMarkerOnlineDot_isFixedAcrossThemes_andNotLightSuccess() {
        #expect(Color.findlyMarkerOnlineDot == Color(hex: 0x52E39B))
        #expect(Color.findlyMarkerOnlineDot != ColorTokens.light.success)
        // It happens to equal dark's `success` (both are #52E39B) — that's a coincidence of this
        // palette, not a rule; the marker dot's correctness must not depend on which theme is active.
        #expect(Color.findlyMarkerOnlineDot == ColorTokens.dark.success)
    }

    @Test func findlyMarkerOnlineDotOn_matchesHandoffValue() {
        // Text drawn on top of the online dot pill (labelSmall "NOW"), per HANDOFF.md MapMarkerBubble.
        #expect(Color.findlyMarkerOnlineDotOn == Color(hex: 0x062418))
    }

    // FindlyButton's disabled label ("Disabled: fill surfaceVariant, label #8D93AB, no shadow" —
    // HANDOFF.md FindlyButton primary). Added post-review: this was a literal `Color(hex:
    // 0x8D93AB)` inline in FindlyButton.swift, violating ColorTokens.swift's own stated invariant
    // ("Components read these fields ONLY, never a literal Color(...)"). WCAG exempts disabled
    // controls, so this isn't a contrast fix — just routing an existing value through a named,
    // additive token so a future palette pass can't silently miss it.
    @Test func findlyDisabledLabel_matchesHandoffValue() {
        #expect(Color.findlyDisabledLabel == Color(hex: 0x8D93AB))
    }

    // FindlyTextField's disabled state ("Disabled: fill #E8EAF2, border #D3D7E6, text #8D93AB" —
    // HANDOFF.md FindlyTextField). Added post-review (code review MAJOR): FindlyTextField never
    // read `@Environment(\.isEnabled)` at all, so a disabled field was visually indistinguishable
    // from an enabled one. Named to mirror Android's `TextFieldDisabledFill/Border/Text` (A26) so
    // the two platforms' additive fields stay legible side by side.
    @Test func findlyTextFieldDisabled_matchesHandoffValues() {
        #expect(Color.findlyTextFieldDisabledFill == Color(hex: 0xE8EAF2))
        #expect(Color.findlyTextFieldDisabledBorder == Color(hex: 0xD3D7E6))
        // Same hex as findlyDisabledLabel (#8D93AB) — the handoff reuses one "disabled text" value
        // across components — but named separately for cross-platform naming symmetry with Android.
        #expect(Color.findlyTextFieldDisabledText == Color(hex: 0x8D93AB))
        #expect(Color.findlyTextFieldDisabledText == Color.findlyDisabledLabel)
    }

    // MARK: - Typography (6 roles: size / weight / line-height / tracking)

    @Test func typography_displayLarge() {
        let t = TypographyTokens.standard.displayLarge
        #expect(t.size == 34)
        #expect(t.weight == .bold)
        #expect(t.lineHeight == 40)
        #expect(t.tracking == -0.4)
    }

    @Test func typography_titleLarge() {
        let t = TypographyTokens.standard.titleLarge
        #expect(t.size == 24)
        #expect(t.weight == .bold)
        #expect(t.lineHeight == 30)
        #expect(t.tracking == -0.2)
    }

    @Test func typography_titleMedium() {
        let t = TypographyTokens.standard.titleMedium
        #expect(t.size == 18)
        #expect(t.weight == .semibold)
        #expect(t.lineHeight == 24)
        #expect(t.tracking == 0)
    }

    @Test func typography_bodyLarge() {
        let t = TypographyTokens.standard.bodyLarge
        #expect(t.size == 17)
        #expect(t.weight == .regular)
        #expect(t.lineHeight == 24)
        #expect(t.tracking == 0)
    }

    @Test func typography_bodyMedium() {
        let t = TypographyTokens.standard.bodyMedium
        #expect(t.size == 15)
        #expect(t.weight == .regular)
        #expect(t.lineHeight == 20)
        #expect(t.tracking == 0)
    }

    @Test func typography_labelSmall() {
        let t = TypographyTokens.standard.labelSmall
        #expect(t.size == 12)
        #expect(t.weight == .bold)
        #expect(t.lineHeight == 16)
        #expect(t.tracking == 0.4)
    }

    @Test func typeStyle_fontIsDerivedFromSizeAndWeight() {
        let t = TypographyTokens.standard.titleMedium
        #expect(t.font == Font.system(size: 18, weight: .semibold))
    }

    // MARK: - Spacing

    @Test func spacing_matchesHandoffScale() {
        let s = SpacingTokens.standard
        #expect(s.xs == 4)
        #expect(s.sm == 8)
        #expect(s.md == 12)
        #expect(s.lg == 20)
        #expect(s.xl == 28)
        #expect(s.xxl == 40)
    }

    // MARK: - Corner radius

    @Test func cornerRadius_matchesHandoffScale() {
        let r = CornerRadiusTokens.standard
        #expect(r.sm == 12)
        #expect(r.md == 20)
        #expect(r.lg == 28)
        #expect(r.pill == 999)
    }

    // MARK: - Elevation: {blur, y, opacity light|dark, color}

    @Test func elevation_light_matchesHandoffTable() {
        let e = ElevationTokens.light
        #expect(e.level0 == ElevationLevel(blur: 0, y: 0, opacity: 0, color: .black))
        #expect(e.level1 == ElevationLevel(blur: 8, y: 2, opacity: 0.10, color: .black))
        #expect(e.level2 == ElevationLevel(blur: 24, y: 8, opacity: 0.14, color: .black))
        #expect(e.level3 == ElevationLevel(blur: 48, y: 16, opacity: 0.18, color: .black))
    }

    @Test func elevation_dark_matchesHandoffTable() {
        let e = ElevationTokens.dark
        #expect(e.level0 == ElevationLevel(blur: 0, y: 0, opacity: 0, color: .black))
        #expect(e.level1 == ElevationLevel(blur: 8, y: 2, opacity: 0.30, color: .black))
        #expect(e.level2 == ElevationLevel(blur: 24, y: 8, opacity: 0.45, color: .black))
        #expect(e.level3 == ElevationLevel(blur: 48, y: 16, opacity: 0.60, color: .black))
    }

    // Shadows are neutral black in both themes (HANDOFF.md "Spacing, radius, elevation") — the one
    // documented exception is a component-level tint (FindlyButton primary), not a token default.
    @Test func elevation_colorIsNeutralBlack_everyLevel_bothThemes() {
        let light = ElevationTokens.light
        let dark = ElevationTokens.dark
        let levels = [light.level0, light.level1, light.level2, light.level3,
                      dark.level0, dark.level1, dark.level2, dark.level3]
        for level in levels {
            #expect(level.color == .black)
        }
    }

    // MARK: - Theme.outlineStrong (contrast-trap #1)
    //
    // Correction (post-review, independently verified — WebAIM formula sanity-checked against
    // #767676-on-#FFFFFF = 4.54:1): the handoff's claim that dark `outline` (#3A4463) "clears
    // 3:1" is wrong — measured 1.99:1 against dark `surface` (#0B0F1C), 1.74:1 against
    // `surfaceVariant` (#161D33). `outlineStrong` therefore uses the SAME #6B739A in both themes
    // (light was already correct at 3.4:1-class; against dark surface it measures 4.13:1, against
    // dark surfaceVariant 3.61:1 — both clear 3:1). Decorative `outline` is unchanged in either
    // theme; only the "carries meaning" strong color is now theme-invariant.

    @Test func outlineStrong_inLight_isTheStrongerColor_notTheDecorativeOutline() {
        #expect(Theme.light.outlineStrong == Color(hex: 0x6B739A))
        #expect(Theme.light.outlineStrong == Color.findlyOutlineStrong)
        #expect(Theme.light.outlineStrong != Theme.light.colors.outline)
    }

    @Test func outlineStrong_inDark_isTheSameStrongColorAsLight_notTheDecorativeOutline() {
        // Dark `outline` (#3A4463) does NOT clear 3:1 (measured 1.99:1 / 1.74:1) despite the
        // handoff's claim — so dark needs `outlineStrong` too, and reuses light's #6B739A rather
        // than a separate dark-tuned value.
        #expect(Theme.dark.outlineStrong == Color(hex: 0x6B739A))
        #expect(Theme.dark.outlineStrong == Color.findlyOutlineStrong)
        #expect(Theme.dark.outlineStrong != Theme.dark.colors.outline)
    }

    // MARK: - Theme.onSurfaceMuted (row subtitles etc. — literal per-scheme hex, not a computed opacity)

    @Test func onSurfaceMuted_matchesHandoffLiteralHexValues() {
        #expect(Theme.light.onSurfaceMuted == Color(hex: 0x4E5675))
        #expect(Theme.dark.onSurfaceMuted == Color(hex: 0x98A1BD))
    }

    // MARK: - Theme.markerOnlineBadge (contrast-trap #2, corrected)
    //
    // The handoff cites 5.4:1 for #52E39B "in both themes", but that ratio is against LIGHT
    // `primary` (#3A46C8) only — independently verified 4.44:1 there (the cited 5.4 was also
    // slightly wrong, harmlessly). Against DARK `primary` (#7C8BFF), #52E39B measures 1.83:1 and
    // fails. Fix: invert the badge in dark — fill #0B3B26 / label #52E39B (fill vs dark primary
    // 4.19:1 ✓, label vs fill 7.69:1 ✓). Green still means online in both themes.

    @Test func markerOnlineBadge_light_usesTheHandoffLiteralFillAndLabel() {
        #expect(Theme.light.markerOnlineBadgeFill == Color.findlyMarkerOnlineDot)
        #expect(Theme.light.markerOnlineBadgeLabel == Color.findlyMarkerOnlineDotOn)
    }

    @Test func markerOnlineBadge_dark_isInvertedForContrastAgainstDarkPrimary() {
        #expect(Theme.dark.markerOnlineBadgeFill == Color(hex: 0x0B3B26))
        #expect(Theme.dark.markerOnlineBadgeLabel == Color.findlyMarkerOnlineDot)
        // The label is still the same fixed "online green" — only fill/label roles swap.
        #expect(Theme.dark.markerOnlineBadgeLabel != Theme.dark.markerOnlineBadgeFill)
    }
}
