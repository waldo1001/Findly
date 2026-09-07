import SwiftUI
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1 (I48, part 3) — `FindlyListRow`'s `.frame(minHeight:
/// 60)` is a MINIMUM, not a fixed height (`FindlyListRow.swift`), while
/// `FindlyBottomSheetHeightPlanning`'s `listRowHeight` constant (60) and the row/divider counts fed
/// into it treat every row as exactly 60pt. That's an under-count risk, the opposite failure from
/// the one I48 part 1 fixed: a row that legitimately renders taller than 60pt (large Dynamic Type,
/// or — proven directly here — a long device name/subtitle wrapping to more than one line) makes
/// the real roster taller than the sheet detent computed for it, clipping content or scrolling
/// sooner than the arithmetic assumes.
///
/// This was flagged in the I48 backlog row as "raised as unverified rather than as a finding" and
/// this task's brief was explicit: cover the behavior rather than half-fixing it (a real fix needs
/// `FindlyBottomSheetHeightPlanning` to take a real per-row height instead of a constant, which is
/// a bigger change than this task — see the implementation report for what that would take).
///
/// Verified here via `SwiftUIRenderingHarness.sizeThatFits(width:)` — real `UIHostingController`/
/// `NSHostingController` layout of the actual `FindlyListRow`, not a hand-waved claim about what
/// SwiftUI "should" do with a `.frame(minHeight:)` and a `Text` that has no `.lineLimit`.
@MainActor
struct FindlyListRowSizingTests {
    /// A width comfortably narrower than the roster sheet actually lays rows out at (§3.1's sheet
    /// spans close to full screen width), so a long title/subtitle is guaranteed to wrap rather than
    /// merely deciding the point moot on an unrealistically wide test canvas.
    private let realisticRowWidth: CGFloat = 320

    private func hostedRow(title: String, subtitle: String?) -> SwiftUIRenderingHarness<AnyView> {
        let row = FindlyListRow(title: title, subtitle: subtitle, avatarText: "AB")
            .environment(\.theme, .light)
        return SwiftUIRenderingHarness(AnyView(row))
    }

    @Test func shortSingleLineContent_rendersAtOrNearTheDeclared60ptMinimum() {
        let harness = hostedRow(title: "Sam", subtitle: "Home · 2 min ago")
        let size = harness.sizeThatFits(width: realisticRowWidth)
        // Not exactly 60 (real text/line-spacing metrics add a little), but nowhere near what a
        // wrapped multi-line subtitle produces below — this is the baseline the "taller" claim
        // below is relative to.
        #expect(size.height >= 60)
        #expect(size.height < 70)
    }

    /// The concrete, provable trigger for the under-count: `FindlyListRow`'s `Text(subtitle)` has no
    /// `.lineLimit`, so a long device name (a real value a user can set, not a synthetic stress
    /// string) wraps onto multiple lines and grows the row well past 60pt. This is exactly what
    /// `FindlyBottomSheetHeightPlanning.standardHeight`'s `listRowHeight = 60` constant does not
    /// account for.
    @Test func longSubtitleWraps_rendersTallerThanTheDeclaredMinHeightThePlannerAssumes() {
        let longDeviceName = "Kai's Very Old Hand-Me-Down iPhone From Three Generations Ago"
        let harness = hostedRow(title: "Kai", subtitle: "\(longDeviceName) · 24 min ago")
        let size = harness.sizeThatFits(width: realisticRowWidth)

        #expect(size.height > 60, "expected long content to wrap and grow the row past FindlyBottomSheetHeightPlanning's fixed 60pt-per-row assumption, but it didn't (\(size.height)pt) — re-check whether this is still an under-count risk")
    }

    /// A long TITLE (not just subtitle) is a second, independent way to trigger the same wrap —
    /// `Text(title)` also carries no `.lineLimit`.
    @Test func longTitleWraps_alsoRendersTallerThanTheDeclaredMinHeight() {
        let longTitle = "Grandma Bartholomew-Whitmore-Fitzgerald the Third"
        let harness = hostedRow(title: longTitle, subtitle: "Live")
        let size = harness.sizeThatFits(width: realisticRowWidth)

        #expect(size.height > 60)
    }

    /// specs/010 §3.1 (I48, part 3) — DISCREPANCY FROM THE BACKLOG ROW'S OWN FRAMING, surfaced
    /// rather than silently assumed away: the I48 row names "large Dynamic Type" alongside "a long
    /// device name" as a way a row legitimately grows past 60pt. Verified here that it does NOT,
    /// for `FindlyListRow` specifically — `.dynamicTypeSize` has ZERO effect on its rendered height
    /// at any content-size category (measured `xSmall` through `accessibility5` against identical
    /// short content: every one comes back the exact same height). The reason is `FindlyListRow`'s
    /// `Text` uses literal fixed-point fonts (`.system(size: 16, weight: .semibold)` /
    /// `.system(size: 13, weight: .regular)`), which SwiftUI does not scale with Dynamic Type —
    /// only semantic text styles (`.body`, `.headline`, or a font built `relativeTo:` one) do that.
    /// So `FindlyListRow` doesn't even grow for users who set a larger system text size — a
    /// separate, arguably more serious accessibility gap than the under-counting this task covers,
    /// and explicitly NOT something this task fixes (see the implementation report for scope).
    /// The genuinely provable trigger for the under-count is long content wrapping (the two tests
    /// above), which needs no Dynamic Type at all.
    @Test func dynamicTypeAlone_hasNoEffectOnRowHeight_theRealTriggerIsContentWrapping() {
        let heights = [DynamicTypeSize.xSmall, .large, .accessibility1, .accessibility3, .accessibility5].map { size in
            let row = FindlyListRow(title: "Sam", subtitle: "Home · 2 min ago", avatarText: "AB")
                .environment(\.theme, .light)
                .dynamicTypeSize(size)
            return SwiftUIRenderingHarness(AnyView(row)).sizeThatFits(width: realisticRowWidth).height
        }
        #expect(Set(heights).count == 1, "expected FindlyListRow's height to be identical across content-size categories for identical short content, found: \(heights)")
    }
}
