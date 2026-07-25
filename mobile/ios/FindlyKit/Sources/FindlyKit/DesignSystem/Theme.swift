/// specs/004-ios-client.md §2.2 — bundles all five token groups. Ship `.light` and `.dark` from
/// day one; a future design pass replaces this file (and the Tokens/ files) without touching
/// anything under `Screens/`, `Navigation/`, `Networking/`, `Auth/`, `Device/`, or `Locations/`.
public struct Theme: Equatable {
    public var colors: ColorTokens
    public var typography: TypographyTokens
    public var spacing: SpacingTokens
    public var corner: CornerRadiusTokens
    public var elevation: ElevationTokens

    public init(colors: ColorTokens, typography: TypographyTokens, spacing: SpacingTokens, corner: CornerRadiusTokens, elevation: ElevationTokens) {
        self.colors = colors
        self.typography = typography
        self.spacing = spacing
        self.corner = corner
        self.elevation = elevation
    }

    public static let light = Theme(colors: .light, typography: .standard, spacing: .standard, corner: .standard, elevation: .standard)
    public static let dark = Theme(colors: .dark, typography: .standard, spacing: .standard, corner: .standard, elevation: .standard)
}
