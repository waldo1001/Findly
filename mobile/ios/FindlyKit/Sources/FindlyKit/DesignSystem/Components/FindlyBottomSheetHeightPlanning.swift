import CoreGraphics

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
/// roster avatar stack's 32pt circles (`RosterAvatarStack.swift`), and the `titleMedium`/
/// `bodyMedium` type roles' declared `TypeStyle.lineHeight` (`TypographyTokens.swift`) — the same
/// value `Theme.light`/`Theme.dark` both resolve to today (spacing/typography don't vary by scheme).
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

    /// specs/010 §3.1 — the `.minimized` detent's content: "Family" title, summary line,
    /// `Locate now` when a member is selected, avatar stack — `LiveMapScreen.minimizedRoster`/
    /// `GroupMapScreen.minimizedRoster`'s `VStack(alignment: .leading, spacing: theme.spacing.sm)`
    /// wrapped in `.padding(theme.spacing.md)`. "Exactly the height its header content needs" (I46
    /// brief): every child height here is a fixed constant, so the only free variable is whether
    /// the `Locate now` row is present.
    public static func minimizedHeight(
        typography: TypographyTokens,
        spacing: SpacingTokens,
        showsLocateNow: Bool
    ) -> CGFloat {
        var childHeights: [CGFloat] = [typography.titleMedium.lineHeight, typography.bodyMedium.lineHeight]
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
        let headerHeight = max(typography.titleMedium.lineHeight, typography.bodyMedium.lineHeight) + spacing.md * 2
        let locateBlock: CGFloat = showsLocateNow ? locateButtonHeight + spacing.sm : 0
        let rows = CGFloat(max(0, rowCount)) * listRowHeight
        let dividers = CGFloat(max(0, dividerCount)) * dividerHeight
        return headerHeight + locateBlock + rows + dividers + grabberAllowance
    }
}
