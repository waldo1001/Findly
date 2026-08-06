import SwiftUI

extension Color {
    /// `0xRRGGBB` convenience initializer for the fixed design-token defaults below.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// specs/004-ios-client.md §2.1 — the semantic color vocabulary, identical to the Android client's
/// token names. Components read these fields ONLY, never a literal `Color(...)`.
public struct ColorTokens: Equatable {
    public var primary: Color
    public var onPrimary: Color
    public var secondary: Color
    public var surface: Color
    public var onSurface: Color
    public var surfaceVariant: Color
    public var danger: Color
    public var onDanger: Color
    public var success: Color
    public var warning: Color
    public var outline: Color

    public init(
        primary: Color, onPrimary: Color, secondary: Color, surface: Color, onSurface: Color,
        surfaceVariant: Color, danger: Color, onDanger: Color, success: Color, warning: Color, outline: Color
    ) {
        self.primary = primary
        self.onPrimary = onPrimary
        self.secondary = secondary
        self.surface = surface
        self.onSurface = onSurface
        self.surfaceVariant = surfaceVariant
        self.danger = danger
        self.onDanger = onDanger
        self.success = success
        self.warning = warning
        self.outline = outline
    }

    // Design direction 2a "Ember / Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md,
    // 2026-08-06) — supersedes the 2026-07-20 teal palette. Every text/essential-icon pairing
    // verified WCAG 2.1 AA (ratios in that handoff and specs/004 §2.1).
    public static let light = ColorTokens(
        primary: Color(hex: 0x3A46C8), onPrimary: Color(hex: 0xFFFFFF), secondary: Color(hex: 0x0E7C8F),
        surface: Color(hex: 0xF2F4FB), onSurface: Color(hex: 0x10142A), surfaceVariant: Color(hex: 0xE2E6F5),
        danger: Color(hex: 0xB3261E), onDanger: Color(hex: 0xFFFFFF), success: Color(hex: 0x10714A),
        warning: Color(hex: 0x8A5A00), outline: Color(hex: 0xA9B0CE)
    )

    public static let dark = ColorTokens(
        primary: Color(hex: 0x7C8BFF), onPrimary: Color(hex: 0x0A0F27), secondary: Color(hex: 0x4FE3D0),
        surface: Color(hex: 0x0B0F1C), onSurface: Color(hex: 0xE8ECF7), surfaceVariant: Color(hex: 0x161D33),
        danger: Color(hex: 0xFF6B6B), onDanger: Color(hex: 0x2A0708), success: Color(hex: 0x52E39B),
        warning: Color(hex: 0xFFC44D), outline: Color(hex: 0x3A4463)
    )
}

// design/findly-design-system/2a-ember-dusk/HANDOFF.md — two theme-invariant colors called out by
// name, both contrast traps a naive substitution would get wrong. Use `Theme.outlineStrong` /
// `Theme.markerOnlineBadgeFill`/`Label` at call sites rather than these directly — those resolve
// the corrections below per scheme.
public extension Color {
    /// Light `outline` (`#A9B0CE`) is decorative-only — legal for hairlines/dividers, not for a
    /// stroke that carries meaning (unselected control border, focus ring, input outline), which
    /// uses this stronger color instead.
    ///
    /// **Correction (post-review, independently verified, two rounds):**
    /// - The handoff claims dark `outline` (`#3A4463`, `ColorTokens.dark.outline`) "clears 3:1"
    ///   and can double for both purposes — that is wrong (measured 1.99:1 vs dark `surface`,
    ///   1.74:1 vs `surfaceVariant`). This color is used in BOTH themes for meaningful strokes;
    ///   see `Theme.outlineStrong`.
    /// - The handoff's own "2.1:1" for decorative light `outline` was also slightly overstated
    ///   (measured 1.95:1 — no threshold applies either way, it's hairline-only), and its "3.4:1"
    ///   for THIS color was understated: measured 4.21:1 vs light `surface`, 3.71:1 vs
    ///   `surfaceVariant` (dark: 4.13:1 / 3.61:1, per the first correction above).
    static let findlyOutlineStrong = Color(hex: 0x6B739A)
    /// The fixed "online green" used by a `primary` marker bubble's "● NOW" pill — as fill in
    /// light, as label in dark (see `Theme.markerOnlineBadgeFill`/`Label`). Light-theme `success`
    /// (`#10714A`) measures 1.2:1 there and must never be substituted in.
    ///
    /// **Correction (post-review, independently verified):** the handoff claims this is "5.4:1 in
    /// both themes" against `primary` — that ratio (independently remeasured at 4.44:1, the
    /// handoff's number was also slightly off) only holds against LIGHT `primary` (`#3A46C8`).
    /// Against dark `primary` (`#7C8BFF`) it measures 1.83:1 and fails outright, which is why dark
    /// inverts fill/label instead of reusing this color as a fill directly.
    static let findlyMarkerOnlineDot = Color(hex: 0x52E39B)
    /// Text drawn on top of `findlyMarkerOnlineDot`.
    static let findlyMarkerOnlineDotOn = Color(hex: 0x062418)
    /// `FindlyButton`'s disabled-state label ("Disabled: fill surfaceVariant, label #8D93AB, no
    /// shadow" — HANDOFF.md FindlyButton primary). WCAG exempts disabled controls, so this isn't
    /// a contrast-driven value; it's named so a future palette pass can't silently skip it the way
    /// an inline literal would let it. The handoff gives only one value (no dark variant), so this
    /// stays theme-invariant like the two colors above until a design pass says otherwise.
    static let findlyDisabledLabel = Color(hex: 0x8D93AB)
    /// `FindlyTextField`'s disabled state ("Disabled: fill #E8EAF2, border #D3D7E6, text #8D93AB"
    /// — HANDOFF.md FindlyTextField). Named to mirror Android's `TextFieldDisabledFill/Border/
    /// Text` (A26, per the code-review round that raised this) so the two platforms' additive
    /// fields stay legible side by side. `findlyTextFieldDisabledText` shares `findlyDisabledLabel`'s
    /// hex (the handoff reuses one "disabled text" value across components) but keeps its own name
    /// for that cross-platform symmetry.
    static let findlyTextFieldDisabledFill = Color(hex: 0xE8EAF2)
    static let findlyTextFieldDisabledBorder = Color(hex: 0xD3D7E6)
    static let findlyTextFieldDisabledText = Color(hex: 0x8D93AB)
}
