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

    // design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md).
    public static let standard = CornerRadiusTokens(sm: 12, md: 20, lg: 28, pill: 999)
}
