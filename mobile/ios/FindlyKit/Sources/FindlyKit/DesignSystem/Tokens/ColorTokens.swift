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
// name, both contrast traps a naive substitution would get wrong:
public extension Color {
    /// Light `outline` (`#A9B0CE`) is only 2.1:1 — legal for decorative hairlines/dividers only.
    /// Any stroke that carries meaning (unselected control border, focus ring, input outline) uses
    /// this stronger color (3.4:1) instead. In dark, `ColorTokens.dark.outline` itself already
    /// clears 3:1 and may be used for both purposes.
    static let findlyOutlineStrong = Color(hex: 0x6B739A)
    /// The dot inside a `primary` marker bubble's "● NOW" pill — fixed at `#52E39B` in BOTH
    /// themes (5.4:1 on `#3A46C8`). Light-theme `success` (`#10714A`) measures 1.2:1 there and
    /// must never be substituted in.
    static let findlyMarkerOnlineDot = Color(hex: 0x52E39B)
    /// Text drawn on top of `findlyMarkerOnlineDot`.
    static let findlyMarkerOnlineDotOn = Color(hex: 0x062418)
}
