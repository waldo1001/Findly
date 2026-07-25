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

    // "Findly — Family Location Design System" (design/findly-design-system/, 2026-07-20).
    // Calm teal-forward palette; every text/essential-icon pairing verified WCAG 2.1 AA
    // (ratios in design/findly-design-system/README.md and specs/004 §2.1).
    public static let light = ColorTokens(
        primary: Color(hex: 0x00696E), onPrimary: Color(hex: 0xFFFFFF), secondary: Color(hex: 0x4C5FD5),
        surface: Color(hex: 0xFAFAF7), onSurface: Color(hex: 0x1B1D1C), surfaceVariant: Color(hex: 0xEEEEE9),
        danger: Color(hex: 0xC0362C), onDanger: Color(hex: 0xFFFFFF), success: Color(hex: 0x1E7D46),
        warning: Color(hex: 0x8A5A00), outline: Color(hex: 0xC9C8C2)
    )

    public static let dark = ColorTokens(
        primary: Color(hex: 0x4CD4D9), onPrimary: Color(hex: 0x00312F), secondary: Color(hex: 0xA9B4FF),
        surface: Color(hex: 0x17181A), onSurface: Color(hex: 0xECECE6), surfaceVariant: Color(hex: 0x24262A),
        danger: Color(hex: 0xF2867B), onDanger: Color(hex: 0x490A05), success: Color(hex: 0x5FD08A),
        warning: Color(hex: 0xE4B44C), outline: Color(hex: 0x3A3D42)
    )
}
