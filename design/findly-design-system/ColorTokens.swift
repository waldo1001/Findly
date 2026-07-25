// Findly — iOS color tokens
// Drop into DesignSystem/Tokens/. Nothing outside DesignSystem should use Color(...) or .font(.system...).
// Assumes a Color(hex:) initializer and the token structs already defined in DesignSystem.

extension ColorTokens {
    static let light = ColorTokens(
        primary:        Color(hex: 0x00696E),
        onPrimary:      Color(hex: 0xFFFFFF),
        secondary:      Color(hex: 0x4C5FD5),
        surface:        Color(hex: 0xFAFAF7),
        onSurface:      Color(hex: 0x1B1D1C),
        surfaceVariant: Color(hex: 0xEEEEE9),
        danger:         Color(hex: 0xC0362C),
        onDanger:       Color(hex: 0xFFFFFF),
        success:        Color(hex: 0x1E7D46),
        warning:        Color(hex: 0x8A5A00),
        outline:        Color(hex: 0xC9C8C2))

    static let dark = ColorTokens(
        primary:        Color(hex: 0x4CD4D9),
        onPrimary:      Color(hex: 0x00312F),
        secondary:      Color(hex: 0xA9B4FF),
        surface:        Color(hex: 0x17181A),
        onSurface:      Color(hex: 0xECECE6),
        surfaceVariant: Color(hex: 0x24262A),
        danger:         Color(hex: 0xF2867B),
        onDanger:       Color(hex: 0x490A05),
        success:        Color(hex: 0x5FD08A),
        warning:        Color(hex: 0xE4B44C),
        outline:        Color(hex: 0x3A3D42))
}

// Typography — platform system font (SF Pro). Sizes in pt.
extension TypographyTokens {
    static let standard = TypographyTokens(
        displayLarge: .system(size: 34, weight: .bold),     // lineHeight 40, tracking -0.68
        titleLarge:   .system(size: 22, weight: .semibold), // lineHeight 28, tracking -0.22
        titleMedium:  .system(size: 17, weight: .semibold), // lineHeight 22
        bodyLarge:    .system(size: 17, weight: .regular),  // lineHeight 24
        bodyMedium:   .system(size: 15, weight: .regular),  // lineHeight 20
        labelSmall:   .system(size: 12, weight: .medium))   // lineHeight 16, tracking 0.4
}

// Spacing (pt), corner radius (pt)
extension SpacingTokens {
    static let standard = SpacingTokens(xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32)
}
extension CornerTokens {
    static let standard = CornerTokens(sm: 8, md: 12, lg: 20, pill: 999)
}

// Elevation as iOS shadow specs { radius (blur), y-offset, opacity }. Shadow color: Color(hex: 0x141914).
extension ElevationTokens {
    static let standard = ElevationTokens(
        level0: nil,
        level1: ShadowSpec(radius: 2, y: 1, opacity: 0.08),
        level2: ShadowSpec(radius: 4, y: 2, opacity: 0.12),
        level3: ShadowSpec(radius: 8, y: 4, opacity: 0.16))
}
