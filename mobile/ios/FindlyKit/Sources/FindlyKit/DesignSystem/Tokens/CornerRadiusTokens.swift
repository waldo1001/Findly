import CoreGraphics

/// specs/004-ios-client.md §2.1 — corner-radius scale in points. `pill` is always large enough to
/// fully round any component regardless of its height.
public struct CornerRadiusTokens: Equatable {
    public var sm: CGFloat
    public var md: CGFloat
    public var lg: CGFloat
    public var pill: CGFloat

    public init(sm: CGFloat, md: CGFloat, lg: CGFloat, pill: CGFloat) {
        self.sm = sm
        self.md = md
        self.lg = lg
        self.pill = pill
    }

    // Findly design system (design/findly-design-system/) — softer, friendlier corners.
    public static let standard = CornerRadiusTokens(sm: 8, md: 12, lg: 20, pill: 999)
}
