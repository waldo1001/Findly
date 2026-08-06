import CoreGraphics

/// specs/004-ios-client.md §2.1 — spacing scale in points.
public struct SpacingTokens: Equatable {
    public var xs: CGFloat
    public var sm: CGFloat
    public var md: CGFloat
    public var lg: CGFloat
    public var xl: CGFloat
    public var xxl: CGFloat

    public init(xs: CGFloat, sm: CGFloat, md: CGFloat, lg: CGFloat, xl: CGFloat, xxl: CGFloat) {
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.xl = xl
        self.xxl = xxl
    }

    // design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md).
    public static let standard = SpacingTokens(xs: 4, sm: 8, md: 12, lg: 20, xl: 28, xxl: 40)
}
