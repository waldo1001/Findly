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

    /// specs/010 §3.1 (I48, part 1) — REWRITTEN from the pre-I48 version, which built its expected
    /// sum from `typography.titleMedium.lineHeight`/`typography.bodyMedium.lineHeight` directly:
    /// that encoded the exact bug I48 closes (the planner trusting the declared, unenforced
    /// `TypeStyle.lineHeight` target as if it were a rendered height). The oracle here is
    /// `FindlyBottomSheetHeightPlanning.renderedLineHeight(for:)` — real `UIFont`/`NSFont` system-
    /// font metrics, the same source the production code now uses — so this still pins the exact
    /// formula (this suite's stated purpose) without re-encoding the old, too-generous behavior.
    @Test func minimizedHeight_withoutLocateNow_sumsTitleSummaryAndAvatarStack() {
        let titleLine = FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.titleMedium)
        let bodyLine = FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.bodyMedium)
        let avatarStack: CGFloat = 32
        let gaps = spacing.sm * 2 // two gaps: title-summary, summary-avatarStack
        let padding = spacing.md * 2 // top+bottom padding
        let grabberAllowance: CGFloat = 24
        let expected = titleLine + bodyLine + avatarStack + gaps + padding + grabberAllowance

        let actual = FindlyBottomSheetHeightPlanning.minimizedHeight(
            typography: typography, spacing: spacing, showsLocateNow: false
        )
        assertApproximatelyEqual(actual, expected)
    }

    /// specs/010 §3.1 (I48, part 1) — the fix itself: real SF Pro metrics for `titleMedium`/
    /// `bodyMedium` are shorter than the declared `TypeStyle.lineHeight` target (the finding behind
    /// row I48 — the planner summing declared targets as if rendered made computed detents "slightly
    /// too generous"). Bounds only (no hardcoded pixel value — exact metrics can shift across OS
    /// releases): strictly positive, and strictly less than the declared target for both roles the
    /// planner consumes.
    @Test func renderedLineHeight_isRealMetrics_shorterThanTheDeclaredTargetForRolesThePlannerUses() {
        let titleRendered = FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.titleMedium)
        let bodyRendered = FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.bodyMedium)

        #expect(titleRendered > 0)
        #expect(bodyRendered > 0)
        #expect(titleRendered < typography.titleMedium.lineHeight)
        #expect(bodyRendered < typography.bodyMedium.lineHeight)
    }

    /// specs/010 §3.1 (I48, part 1) — `renderedLineHeight` is a pure function of size+weight: same
    /// input, same output, every call. Guards against a future change accidentally threading in
    /// something environment-dependent (e.g. live view measurement) that would reintroduce the
    /// "collapses to zero for a second simultaneous render" failure mode this file's own header doc
    /// already warns `FindlyBottomSheetHeightPlanning` was built to avoid.
    @Test func renderedLineHeight_isDeterministic() {
        let a = FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.titleMedium)
        let b = FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.titleMedium)
        assertApproximatelyEqual(a, b)
    }

    /// specs/010 §3.1 (I48, part 1) — `standardHeight`'s `headerHeight` term also stopped trusting
    /// the declared token; this proves it end-to-end by comparing the real function's output against
    /// what the OLD (declared-lineHeight-based) formula would have produced for the identical inputs.
    /// The two must differ — if they don't, the fix silently regressed back to summing targets.
    @Test func standardHeight_headerTerm_usesRealMetrics_notTheDeclaredLineHeightTarget() {
        let oldDeclaredHeaderHeight = max(typography.titleMedium.lineHeight, typography.bodyMedium.lineHeight) + spacing.md * 2
        let realHeaderHeight = max(
            FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.titleMedium),
            FindlyBottomSheetHeightPlanning.renderedLineHeight(for: typography.bodyMedium)
        ) + spacing.md * 2

        let actual = FindlyBottomSheetHeightPlanning.standardHeight(
            typography: typography, spacing: spacing, showsLocateNow: false, rowCount: 0, dividerCount: 0
        )
        let oldFormulaResult = oldDeclaredHeaderHeight + 24 // grabberAllowance, rowCount/dividerCount/locateBlock all 0
        let newFormulaResult = realHeaderHeight + 24

        assertApproximatelyEqual(actual, newFormulaResult)
        #expect(abs(actual - oldFormulaResult) > 0.01, "expected the fix to change the result, but it matched the old declared-lineHeight formula exactly")
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
