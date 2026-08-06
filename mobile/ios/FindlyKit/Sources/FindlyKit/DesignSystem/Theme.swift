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
    /// decorative `outline` (`#A9B0CE` light / `#3A4463` dark) is legal only for hairlines/
    /// dividers. Any stroke that carries meaning (an unselected control border, a focus ring, an
    /// input outline) MUST use this instead.
    ///
    /// **Correction (post-review, independently verified, two rounds):**
    /// - The handoff claims dark `outline` "clears 3:1" and can double as both decorative and
    ///   meaningful — that is wrong. Measured: `#3A4463` vs dark `surface` (`#0B0F1C`) = 1.99:1;
    ///   vs `surfaceVariant` (`#161D33`) = 1.74:1. Both themes therefore use the SAME `#6B739A`
    ///   for meaningful strokes; decorative `outline` stays unchanged in either theme.
    /// - The handoff's own ratios for THIS color were also off, understated this time: measured
    ///   4.21:1 vs light `surface` / 3.71:1 vs `surfaceVariant` (not "3.4:1-class"), and 4.13:1 /
    ///   3.61:1 in dark (both clear 3:1, per the first correction). Light decorative `outline`'s
    ///   cited "2.1:1" was also slightly overstated (measured 1.95:1 — moot, hairline-only).
    var outlineStrong: Color { .findlyOutlineStrong }

    /// `onSurface` at ~70% opacity, using literal per-scheme hex values (e.g. `FindlyListRow`
    /// subtitles) rather than a computed `.opacity(0.7)` — a computed opacity blends differently
    /// depending on what's behind it.
    ///
    /// **Correction, I30 (specs/004 §2.1), mirrors Android's A30.** Light darkened from
    /// HANDOFF.md's literal `#4E5675` to `#3A4160` — for cross-platform consistency, not because
    /// iOS was observed failing. A user reported light mode hard to read on a real Android device
    /// but explicitly said iOS looked fine with the identical value; sampling the rendered Android
    /// pixels found `#4E5675` on `#F2F4FB` exactly, rendering the design faithfully at 6.56:1 —
    /// passing AA but thin for a low-chroma color at 13pt/13sp subtitles and section headers. The
    /// plausible reason iOS didn't draw the same complaint is that SF renders heavier than Roboto
    /// at these sizes, or that the screens looked at differed — neither is asserted as fact, only
    /// plausible. `#3A4160` measures 9.08:1 on `surface` / 8.01:1 on `surfaceVariant` (independently
    /// verified), still clearly a secondary tier against `onSurface` `#10142A` (16.54:1). Dark
    /// `#98A1BD` is unchanged: already 7.43:1 / 6.49:1, materially better than light's old value,
    /// which is probably why dark never drew a complaint on either platform.
    var onSurfaceMuted: Color {
        colors == ColorTokens.light ? Color(hex: 0x3A4160) : Color(hex: 0x98A1BD)
    }

    /// The "● NOW" badge inside a `.normal` `MapMarkerBubble` (contrast trap #2, corrected).
    ///
    /// The handoff cites `#52E39B` at "5.4:1 in both themes", but that ratio is against LIGHT
    /// `primary` (`#3A46C8`) only — independently verified 4.44:1 there (the cited 5.4 was also
    /// slightly wrong, harmlessly). Against DARK `primary` (`#7C8BFF`), `#52E39B` measures only
    /// 1.83:1 and fails outright. Fix: invert the badge in dark rather than reuse the light
    /// pairing — fill `#0B3B26` vs dark bubble `#7C8BFF` = 4.19:1 ✓; label `#52E39B` on that fill
    /// = 7.69:1 ✓. Green still means online in both themes; only which role (fill vs label) it
    /// plays swaps.
    var markerOnlineBadgeFill: Color {
        colors == ColorTokens.light ? .findlyMarkerOnlineDot : Color(hex: 0x0B3B26)
    }

    /// See `markerOnlineBadgeFill`.
    var markerOnlineBadgeLabel: Color {
        colors == ColorTokens.light ? .findlyMarkerOnlineDotOn : .findlyMarkerOnlineDot
    }
}
