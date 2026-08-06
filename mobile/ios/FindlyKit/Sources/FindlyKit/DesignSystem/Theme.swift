import SwiftUI

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

    public static let light = Theme(colors: .light, typography: .standard, spacing: .standard, corner: .standard, elevation: .light)
    public static let dark = Theme(colors: .dark, typography: .standard, spacing: .standard, corner: .standard, elevation: .dark)
}

public extension Theme {
    /// design 2a "Ember/Dusk" contrast trap (design/findly-design-system/2a-ember-dusk/HANDOFF.md):
    /// light `outline` (`#A9B0CE`) is only 2.1:1 — legal for decorative hairlines/dividers only.
    /// Any stroke that carries meaning (an unselected control border, a focus ring, an input
    /// outline) MUST use this instead. In dark, `colors.outline` itself already clears 3:1, so it
    /// doubles for both purposes and this simply returns it unchanged.
    var outlineStrong: Color {
        colors == ColorTokens.light ? .findlyOutlineStrong : colors.outline
    }

    /// `onSurface` at ~70% opacity, using the handoff's literal per-scheme hex values (e.g.
    /// `FindlyListRow` subtitles) rather than a computed `.opacity(0.7)` — the handoff gives exact
    /// hexes because a computed opacity blends differently depending on what's behind it.
    var onSurfaceMuted: Color {
        colors == ColorTokens.light ? Color(hex: 0x4E5675) : Color(hex: 0x98A1BD)
    }
}
