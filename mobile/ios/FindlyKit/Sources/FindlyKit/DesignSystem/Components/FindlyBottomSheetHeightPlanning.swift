import CoreGraphics
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// specs/010-app-shell-and-screen-ux.md §3.1 (amended 2026-08-27, row I46 — `39e92a4`) — pure
/// arithmetic backing `FindlyBottomSheet`'s `minimizedHeight`/`standardHeight` parameters. See that
/// file's header doc for why this is computed rather than runtime-measured: a hidden-probe
/// `GeometryReader` measurement collapses to zero for a `ForEach` (or any `@FocusState`-holding
/// view, e.g. `FindlyButton`) rendered a second, simultaneous time in the same `.sheet` presentation
/// — exactly the shape a member roster needs.
///
/// Every constant below is a component's own DOCUMENTED, fixed geometry — never a runtime
/// measurement of that component — so this stays exactly as stable as the design system itself:
/// `FindlyListRow`'s `minHeight: 60`, `FindlyButton`'s 52pt height, `FindlyCardDivider`'s 1pt, the
/// roster avatar stack's 32pt circles (`RosterAvatarStack.swift`). The one exception is the
/// `titleMedium`/`bodyMedium` line heights: this does NOT use `TypeStyle.lineHeight`
/// (`TypographyTokens.swift`) — that field is a design *target* nothing in this file's call path
/// applies (see its own doc comment) — it uses `renderedLineHeight(for:)` below, real `UIFont`/
/// `NSFont` system-font metrics for the role's actual size+weight, i.e. what SF Pro really renders
/// at that size (specs/010 §3.1, row I48: summing the declared target as if it were rendered made
/// computed detents "slightly too generous").
/// `grabberAllowance` is the one approximation: `.presentationDragIndicator(.visible)` reserves
/// space for the system-drawn grab handle above this content that neither this type nor the caller
/// otherwise accounts for; it is intentionally generous (erring toward a sliver of headroom rather
/// than clipping the caller's last line).
public enum FindlyBottomSheetHeightPlanning {
    private static let listRowHeight: CGFloat = 60
    private static let locateButtonHeight: CGFloat = 52
    private static let dividerHeight: CGFloat = 1
    private static let avatarStackHeight: CGFloat = 32
    private static let grabberAllowance: CGFloat = 24

    /// specs/010 §3.1 (I48, part 1) — the REAL rendered line height for a `TypeStyle`'s size+weight,
    /// sourced from `UIFont`/`NSFont` system-font metrics (the same San Francisco font data
    /// SwiftUI's `.system(size:weight:)` resolves to) rather than `TypeStyle.lineHeight`, which is
    /// an unenforced design target (see that property's doc). Line height = ascent + descent +
    /// leading, rounded up — the same formula `UIFont.lineHeight` itself uses on iOS; the `AppKit`
    /// branch reproduces it by hand since `NSFont` has no equivalent convenience property. The
    /// `#if canImport` split mirrors `SwiftUIRenderingHarness`'s (FindlyKitTests) — `swift test`
    /// with no `-destination` builds against the macOS host SDK (`AppKit` branch); `xcodebuild`
    /// against an iOS Simulator destination takes the `UIKit` branch. Both query the same font
    /// engine, so both report the same metrics for the same input.
    static func renderedLineHeight(for style: TypeStyle) -> CGFloat {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: style.size, weight: UIFont.Weight(systemWeightValue(style.weight)))
        return font.lineHeight
        #elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: style.size, weight: NSFont.Weight(systemWeightValue(style.weight)))
        return (font.ascender - font.descender + font.leading).rounded(.up)
        #else
        return style.lineHeight
        #endif
    }

    /// Maps SwiftUI's `Font.Weight` to the numeric scale `UIFont.Weight`/`NSFont.Weight` share
    /// (`UIFontWeightXXX`/`NSFontWeightXXX` — the same constants underlie both; `Font.Weight` itself
    /// exposes no way to read this back out). Values per Apple's documented weight scale.
    private static func systemWeightValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: return -0.8
        case .thin: return -0.6
        case .light: return -0.4
        case .regular: return 0
        case .medium: return 0.23
        case .semibold: return 0.3
        case .bold: return 0.4
        case .heavy: return 0.56
        case .black: return 0.62
        default: return 0
        }
    }

    /// specs/010 §3.1 — the `.minimized` detent's content: "Family" title, summary line,
    /// `Locate now` when a member is selected, avatar stack — `LiveMapScreen.minimizedRoster`/
    /// `GroupMapScreen.minimizedRoster`'s `VStack(alignment: .leading, spacing: theme.spacing.sm)`
    /// wrapped in `.padding(theme.spacing.md)`. "Exactly the height its header content needs" (I46
    /// brief): every child height here is a fixed constant (or, for the title/summary lines, a real
    /// measured font metric via `renderedLineHeight` — I48), so the only free variable is whether
    /// the `Locate now` row is present.
    public static func minimizedHeight(
        typography: TypographyTokens,
        spacing: SpacingTokens,
        showsLocateNow: Bool
    ) -> CGFloat {
        var childHeights: [CGFloat] = [renderedLineHeight(for: typography.titleMedium), renderedLineHeight(for: typography.bodyMedium)]
        if showsLocateNow { childHeights.append(locateButtonHeight) }
        childHeights.append(avatarStackHeight)

        let gaps = CGFloat(childHeights.count - 1) * spacing.sm
        let content = childHeights.reduce(0, +) + gaps
        return content + spacing.md * 2 + grabberAllowance
    }

    /// specs/010 §3.1 — the `.standard` detent's content: header (title + Refresh) + the optional
    /// `Locate now` row + however many member rows exist — `LiveMapScreen.fullRoster`/
    /// `GroupMapScreen.fullRoster`'s header `HStack` (padded `theme.spacing.md`), then the roster.
    /// The caller passes flattened `rowCount`/`dividerCount` because only it knows the real shape
    /// (the Family Map's `fullRoster` renders one `FindlyListRow` per DEVICE, with a divider between
    /// a member's own devices as well as after each member; the Group Map renders exactly one row
    /// and one divider per member) — this function stays presentation-shape-agnostic arithmetic.
    /// Capping the result at the platform "large" detent is the CALLER's job via
    /// `findlyBottomSheet`'s `standardHeightCap` — this always returns the uncapped, full total.
    public static func standardHeight(
        typography: TypographyTokens,
        spacing: SpacingTokens,
        showsLocateNow: Bool,
        rowCount: Int,
        dividerCount: Int
    ) -> CGFloat {
        let headerHeight = max(renderedLineHeight(for: typography.titleMedium), renderedLineHeight(for: typography.bodyMedium)) + spacing.md * 2
        let locateBlock: CGFloat = showsLocateNow ? locateButtonHeight + spacing.sm : 0
        let rows = CGFloat(max(0, rowCount)) * listRowHeight
        let dividers = CGFloat(max(0, dividerCount)) * dividerHeight
        return headerHeight + locateBlock + rows + dividers + grabberAllowance
    }
}
