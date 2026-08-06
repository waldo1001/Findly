import SwiftUI

/// specs/004-ios-client.md §2.1 — one type role: size, weight, line-height and tracking. SwiftUI
/// has no single `Font` property that carries line-height/tracking, so those ship as companion
/// scalars a component applies via `.tracking(_:)` / `.lineSpacing(_:)` alongside `.font(_:)`.
public struct TypeStyle: Equatable {
    public var size: CGFloat
    public var weight: Font.Weight
    /// Target line height in points. SwiftUI's closest primitive is `.lineSpacing(_:)`, which adds
    /// *extra* space between lines rather than setting an absolute line height — components apply
    /// `.lineSpacing(lineHeight - size)` as the practical approximation.
    public var lineHeight: CGFloat
    public var tracking: CGFloat

    public init(size: CGFloat, weight: Font.Weight, lineHeight: CGFloat, tracking: CGFloat) {
        self.size = size
        self.weight = weight
        self.lineHeight = lineHeight
        self.tracking = tracking
    }

    public var font: Font { .system(size: size, weight: weight) }
}

/// specs/004-ios-client.md §2.1 — the six type roles, identical across light/dark (typography
/// doesn't change with color scheme, but is exposed via `Theme` regardless so a future design pass
/// can still override it uniformly).
public struct TypographyTokens: Equatable {
    public var displayLarge: TypeStyle
    public var titleLarge: TypeStyle
    public var titleMedium: TypeStyle
    public var bodyLarge: TypeStyle
    public var bodyMedium: TypeStyle
    public var labelSmall: TypeStyle

    public init(displayLarge: TypeStyle, titleLarge: TypeStyle, titleMedium: TypeStyle, bodyLarge: TypeStyle, bodyMedium: TypeStyle, labelSmall: TypeStyle) {
        self.displayLarge = displayLarge
        self.titleLarge = titleLarge
        self.titleMedium = titleMedium
        self.bodyLarge = bodyLarge
        self.bodyMedium = bodyMedium
        self.labelSmall = labelSmall
    }

    // design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md) — SF Pro
    // system font. `labelSmall` renders uppercase at the call site (FindlySectionHeader, StatusChip)
    // — uppercasing is a presentational choice, not a token property.
    public static let standard = TypographyTokens(
        displayLarge: TypeStyle(size: 34, weight: .bold, lineHeight: 40, tracking: -0.4),
        titleLarge: TypeStyle(size: 24, weight: .bold, lineHeight: 30, tracking: -0.2),
        titleMedium: TypeStyle(size: 18, weight: .semibold, lineHeight: 24, tracking: 0),
        bodyLarge: TypeStyle(size: 17, weight: .regular, lineHeight: 24, tracking: 0),
        bodyMedium: TypeStyle(size: 15, weight: .regular, lineHeight: 20, tracking: 0),
        labelSmall: TypeStyle(size: 12, weight: .bold, lineHeight: 16, tracking: 0.4)
    )
}
