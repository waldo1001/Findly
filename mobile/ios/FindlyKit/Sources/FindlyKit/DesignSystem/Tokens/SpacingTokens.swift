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

    public static let standard = SpacingTokens(xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32)
}
