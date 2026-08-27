import CoreGraphics
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.1 (amended 2026-08-27, row I46) — pure arithmetic, no
/// SwiftUI hosting needed. Pins the exact formulas `FindlyBottomSheetHeightPlanning` uses so a
/// future edit can't silently drift from the component constants it's built on.
struct FindlyBottomSheetHeightPlanningTests {
    private let typography = TypographyTokens.standard
    private let spacing = SpacingTokens.standard

    /// `CGFloat`/`Double` equality through `#expect(a == b)` is best avoided for computed sums —
    /// compare with a tight tolerance instead.
    private func assertApproximatelyEqual(_ a: CGFloat, _ b: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a - b) < 0.01, "\(a) is not approximately \(b)", sourceLocation: sourceLocation)
    }

    @Test func minimizedHeight_withoutLocateNow_sumsTitleSummaryAndAvatarStack() {
        let expected = typography.titleMedium.lineHeight
            + typography.bodyMedium.lineHeight
            + 32 // avatar stack
            + spacing.sm * 2 // two gaps: title-summary, summary-avatarStack
            + spacing.md * 2 // top+bottom padding
            + 24 // grabber allowance
        let actual = FindlyBottomSheetHeightPlanning.minimizedHeight(
            typography: typography, spacing: spacing, showsLocateNow: false
        )
        assertApproximatelyEqual(actual, expected)
    }

    @Test func minimizedHeight_withLocateNow_addsTheButtonHeightAndAnExtraGap() {
        let without = FindlyBottomSheetHeightPlanning.minimizedHeight(
            typography: typography, spacing: spacing, showsLocateNow: false
        )
        let with = FindlyBottomSheetHeightPlanning.minimizedHeight(
            typography: typography, spacing: spacing, showsLocateNow: true
        )
        // +52 (the button) + one more spacing.sm gap than the no-button case.
        assertApproximatelyEqual(with, without + 52 + spacing.sm)
    }

    @Test func minimizedHeight_neverDependsOnRowCount() {
        // 010 §3.1: "exactly the height its header content needs" — minimized has no member rows.
        let a = FindlyBottomSheetHeightPlanning.minimizedHeight(typography: typography, spacing: spacing, showsLocateNow: true)
        let b = FindlyBottomSheetHeightPlanning.minimizedHeight(typography: typography, spacing: spacing, showsLocateNow: true)
        assertApproximatelyEqual(a, b)
    }

    @Test func standardHeight_growsLinearlyWithRowCount() {
        let zeroRows = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: 0, dividerCount: 0
        )
        let fourRows = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: 4, dividerCount: 4
        )
        // 4 rows * 60 + 4 dividers * 1 more than the zero-row baseline.
        assertApproximatelyEqual(fourRows, zeroRows + 4 * 60 + 4 * 1)
    }

    @Test func standardHeight_withLocateNow_addsTheButtonBlock() {
        let without = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: 4, dividerCount: 4
        )
        let with = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: true, rowCount: 4, dividerCount: 4
        )
        assertApproximatelyEqual(with, without + 52 + spacing.sm)
    }

    @Test func standardHeight_negativeCountsClampToZero_neverGoesNegativeOrCrashes() {
        let clamped = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: -1, dividerCount: -1
        )
        let zero = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: 0, dividerCount: 0
        )
        assertApproximatelyEqual(clamped, zero)
    }

    @Test func standardHeight_forAFourMemberFamily_isComfortablyBelowTheOldFixed440ptHandoffValue() {
        // The I46 problem statement itself: a real 4-member family's standard detent used to leave
        // dead space below its content at the handoff's fixed 440pt. The measured content for 4
        // single-device members (header + 4 rows + 4 dividers, no selection) should land well
        // under that, proving the fix actually shrinks the detent rather than reproducing the bug.
        let height = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: 4, dividerCount: 4
        )
        #expect(height < 440)
    }
}
