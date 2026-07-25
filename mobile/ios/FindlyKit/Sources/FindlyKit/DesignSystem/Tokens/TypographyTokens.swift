import SwiftUI

/// specs/004-ios-client.md §2.1 — the six type roles, identical across light/dark (typography
/// doesn't change with color scheme, but is exposed via `Theme` regardless so a future design pass
/// can still override it uniformly).
public struct TypographyTokens: Equatable {
    public var displayLarge: Font
    public var titleLarge: Font
    public var titleMedium: Font
    public var bodyLarge: Font
    public var bodyMedium: Font
    public var labelSmall: Font

    public init(displayLarge: Font, titleLarge: Font, titleMedium: Font, bodyLarge: Font, bodyMedium: Font, labelSmall: Font) {
        self.displayLarge = displayLarge
        self.titleLarge = titleLarge
        self.titleMedium = titleMedium
        self.bodyLarge = bodyLarge
        self.bodyMedium = bodyMedium
        self.labelSmall = labelSmall
    }

    // Findly design system (design/findly-design-system/) — SF Pro system font. `titleLarge` is
    // Semibold (was Bold) per the unified type scale. Line-height/tracking (design README) are
    // applied by components at render; the token contract's type is `Font`.
    public static let standard = TypographyTokens(
        displayLarge: .system(size: 34, weight: .bold),
        titleLarge: .system(size: 22, weight: .semibold),
        titleMedium: .system(size: 17, weight: .semibold),
        bodyLarge: .system(size: 17, weight: .regular),
        bodyMedium: .system(size: 15, weight: .regular),
        labelSmall: .system(size: 12, weight: .medium)
    )
}
