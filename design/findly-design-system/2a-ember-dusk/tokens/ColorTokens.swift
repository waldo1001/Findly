import SwiftUI

// Findly direction 2a — "Ember / Dusk"
// Ember layout, type, spacing and shape; Dusk colour values.

extension ColorTokens {
  static let light = ColorTokens(
    primary:        Color(hex: 0x3A46C8),
    onPrimary:      Color(hex: 0xFFFFFF),
    secondary:      Color(hex: 0x0E7C8F),
    surface:        Color(hex: 0xF2F4FB),
    onSurface:      Color(hex: 0x10142A),
    surfaceVariant: Color(hex: 0xE2E6F5),
    danger:         Color(hex: 0xB3261E),
    onDanger:       Color(hex: 0xFFFFFF),
    success:        Color(hex: 0x10714A),
    warning:        Color(hex: 0x8A5A00),
    outline:        Color(hex: 0xA9B0CE)
  )

  static let dark = ColorTokens(
    primary:        Color(hex: 0x7C8BFF),
    onPrimary:      Color(hex: 0x0A0F27),
    secondary:      Color(hex: 0x4FE3D0),
    surface:        Color(hex: 0x0B0F1C),
    onSurface:      Color(hex: 0xE8ECF7),
    surfaceVariant: Color(hex: 0x161D33),
    danger:         Color(hex: 0xFF6B6B),
    onDanger:       Color(hex: 0x2A0708),
    success:        Color(hex: 0x52E39B),
    warning:        Color(hex: 0xFFC44D),
    outline:        Color(hex: 0x3A4463)
  )
}

// Light `outline` is 2.1:1 — decorative hairlines only.
// Strokes that carry meaning use this instead (3.4:1).
extension Color {
  static let findlyOutlineStrong = Color(hex: 0x6B739A)
  // Online dot inside a `primary` marker bubble, both themes (5.4:1 on primary).
  static let findlyMarkerOnlineDot = Color(hex: 0x52E39B)
  static let findlyMarkerOnlineDotOn = Color(hex: 0x062418)
}

enum FindlyRadius {
  static let sm: CGFloat = 12
  static let md: CGFloat = 20
  static let lg: CGFloat = 28
  static let pill: CGFloat = 999
}

enum FindlySpacing {
  static let xs: CGFloat = 4
  static let sm: CGFloat = 8
  static let md: CGFloat = 12
  static let lg: CGFloat = 20
  static let xl: CGFloat = 28
  static let xxl: CGFloat = 40
}

// blur, y-offset, opacity in light, opacity in dark. Shadow colour is always black.
enum FindlyShadow {
  static let level1 = (blur:  8.0, y:  2.0, opacity: 0.10, opacityDark: 0.30)
  static let level2 = (blur: 24.0, y:  8.0, opacity: 0.14, opacityDark: 0.45)
  static let level3 = (blur: 48.0, y: 16.0, opacity: 0.18, opacityDark: 0.60)
}

enum FindlyType {
  static let displayLarge = (size: 34.0, weight: Font.Weight.bold,     line: 40.0, tracking: -0.4)
  static let titleLarge   = (size: 24.0, weight: Font.Weight.bold,     line: 30.0, tracking: -0.2)
  static let titleMedium  = (size: 18.0, weight: Font.Weight.semibold, line: 24.0, tracking:  0.0)
  static let bodyLarge    = (size: 17.0, weight: Font.Weight.regular,  line: 24.0, tracking:  0.0)
  static let bodyMedium   = (size: 15.0, weight: Font.Weight.regular,  line: 20.0, tracking:  0.0)
  static let labelSmall   = (size: 12.0, weight: Font.Weight.bold,     line: 16.0, tracking:  0.4)
}
