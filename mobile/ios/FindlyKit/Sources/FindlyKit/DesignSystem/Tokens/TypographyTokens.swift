import SwiftUI

/// specs/004-ios-client.md §2.1 — one type role: size, weight, line-height and tracking. SwiftUI
/// has no single `Font` property that carries line-height/tracking, so those ship as companion
/// scalars a component applies via `.tracking(_:)` / `.lineSpacing(_:)` alongside `.font(_:)`.
public struct TypeStyle: Equatable {
    public var size: CGFloat
    public var weight: Font.Weight
    /// Target line height in points — a design intent, NOT automatically applied. SwiftUI has no
    /// primitive that sets an absolute line height; the modifier that would approximate it,
    /// `.lineSpacing(lineHeight - size)`, appears in exactly two places in the whole design system
    /// (`ErrorStateView.swift:35`, `EmptyStateView.swift:31`) — and both of those use a different,
    /// ad hoc formula (`size * 1.5 - size`), not this value. Everywhere else this field is declared
    /// but unenforced; do not assume a `Text` using this role actually renders at this line height.
    /// (specs/010 §3.1, row I48 — found because `FindlyBottomSheetHeightPlanning` trusted this
    /// target as if it were a rendered height, making computed sheet detents slightly too generous;
    /// that planner now derives real line heights from `UIFont`/`NSFont` system-font metrics
    /// instead — see `FindlyBottomSheetHeightPlanning.renderedLineHeight(for:)` — rather than this
    /// property, and applying `.lineSpacing` app-wide to make this field true was deliberately not
    /// done in that fix, for lack of any way to visually verify a typography-wide change today.)
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
