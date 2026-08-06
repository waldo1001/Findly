import SwiftUI
import Testing
@testable import FindlyKit

/// I29 (specs/004-ios-client §2.1) — fails the build when any declared token pairing in
/// `ColorContrastPairings.swift` drops below its WCAG 2.1 threshold. Written after applying
/// design 2a surfaced seven measured discrepancies in
/// `design/findly-design-system/2a-ember-dusk/HANDOFF.md`'s own contrast table, four of which
/// would have shipped as real accessibility failures — this app is used outdoors in bright sun by
/// a parent looking for a child, so contrast here is a safety property, not a style preference.
///
/// `WCAGContrastFormulaTests.swift` sanity-checks the formula itself first; everything below
/// trusts it.
struct ColorContrastPairingsTests {

    // MARK: - Text at 4.5:1

    @Test(arguments: ColorContrastPairings.textPairings)
    func textPairing_meetsWCAG_4_5(_ pairing: ColorContrastPairings.TextOrStrokePairing) {
        let ratio = WCAGContrast.ratio(pairing.foreground, pairing.background)
        #expect(
            ratio >= pairing.threshold,
            """
            "\(pairing.name)" (\(pairing.scheme.rawValue)) measures \(ratio):1, below the \
            \(pairing.threshold):1 text threshold (WCAG 2.1 SC 1.4.3). If this is one of the four \
            known-bad handoff numbers, it should already be fixed at the token level — see \
            ColorContrastPairingsTests's pinned-regression tests. If this is a NEW failure, stop \
            and report rather than adjusting the threshold or the color (I29 task instructions).
            """
        )
    }

    // MARK: - Meaningful strokes / graphical objects at 3:1

    @Test(arguments: ColorContrastPairings.strokePairings)
    func strokePairing_meetsWCAG_3_0(_ pairing: ColorContrastPairings.TextOrStrokePairing) {
        let ratio = WCAGContrast.ratio(pairing.foreground, pairing.background)
        #expect(
            ratio >= pairing.threshold,
            """
            "\(pairing.name)" (\(pairing.scheme.rawValue)) measures \(ratio):1, below the \
            \(pairing.threshold):1 meaningful-stroke threshold (WCAG 2.1 SC 1.4.11). Stop and \
            report rather than adjusting the threshold or the color if this is unexpected.
            """
        )
    }

    // MARK: - Component pairs at 4.5:1

    @Test(arguments: ColorContrastPairings.componentPairings)
    func componentPairing_meetsWCAG_4_5(_ pairing: ColorContrastPairings.TextOrStrokePairing) {
        let ratio = WCAGContrast.ratio(pairing.foreground, pairing.background)
        #expect(
            ratio >= pairing.threshold,
            """
            "\(pairing.name)" (\(pairing.scheme.rawValue)) measures \(ratio):1, below the \
            \(pairing.threshold):1 component threshold (WCAG 2.1 SC 1.4.3). Stop and report \
            rather than adjusting the threshold or the color if this is unexpected.
            """
        )
    }

    // MARK: - Decorative exemption, explicit (I29 task item 5)
    //
    // Light `outline` (#A9B0CE) is legal ONLY as a decorative hairline/divider — WCAG doesn't
    // apply a contrast threshold to purely decorative, non-meaningful graphics (SC 1.4.11's own
    // scope note). It measures well under 3:1 against light `surface`, and that is fine BY
    // DESIGN. This test states the rule explicitly, pins the real number, and must never be
    // "fixed" by raising the threshold or recoloring `outline` — any stroke that carries meaning
    // uses `outlineStrong` instead (see the stroke pairings above).
    @Test func decorativeOutline_light_isBelowStrokeThreshold_documentedExemption() {
        let ratio = WCAGContrast.ratio(Theme.light.colors.outline, Theme.light.colors.surface)
        #expect(abs(ratio - 1.95) < 0.01, "light decorative `outline`/`surface` drifted off its documented 1.95:1 — specs/004 §2.1.")
        #expect(ratio < 3.0, "light decorative `outline` is expected to fail the 3:1 meaningful-stroke bar — it's a documented hairline-only exemption, not a defect.")
    }

    // MARK: - Pinned regressions: the four values that actually failed (I29 task item 4)

    // 1. dark `outline` (#3A4463) vs dark `surface` = 1.99:1 — the handoff claimed this "clears
    //    3:1" and could double as a meaningful stroke. It can't. `outlineStrong` is the fix; raw
    //    `outline` must stay documented as failing so nobody points a meaningful stroke back at it.
    @Test func darkOutline_failsStrokeThreshold_butOutlineStrongPasses() {
        let outlineRatio = WCAGContrast.ratio(Theme.dark.colors.outline, Theme.dark.colors.surface)
        #expect(abs(outlineRatio - 1.99) < 0.01, "dark `outline`/`surface` drifted off its documented (and known-wrong-in-the-handoff) 1.99:1.")
        #expect(outlineRatio < 3.0, "dark `outline` must stay below 3:1 as a live regression guard — HANDOFF.md's claim that it 'clears 3:1' was wrong.")

        let outlineStrongRatio = WCAGContrast.ratio(Theme.dark.outlineStrong, Theme.dark.colors.surface)
        #expect(outlineStrongRatio >= 3.0, "`outlineStrong` (the correct token for meaningful strokes in dark) must pass 3:1 where raw `outline` fails.")
    }

    // 2. dark marker pill fill vs dark `primary` (#7C8BFF): the OLD (never-shipped-for-dark)
    //    value #52E39B measured 1.83:1 and failed; the SHIPPED fix `Theme.markerOnlineBadgeFill`
    //    (#0B3B26) measures 4.19:1 and passes. Guards against ever reusing the light fill in dark.
    @Test func darkMarkerPillFill_shippedValuePasses_oldValueWouldHaveFailed() {
        let shippedRatio = WCAGContrast.ratio(Theme.dark.markerOnlineBadgeFill, Theme.dark.colors.primary)
        #expect(abs(shippedRatio - 4.19) < 0.01, "shipped dark marker pill fill (#0B3B26) vs dark `primary` drifted off its documented 4.19:1.")
        #expect(shippedRatio >= 3.0)

        let oldRatio = WCAGContrast.ratio(Color.findlyMarkerOnlineDot, Theme.dark.colors.primary)
        #expect(abs(oldRatio - 1.83) < 0.01, "the old #52E39B-as-dark-fill ratio drifted off its documented (and known-failing) 1.83:1.")
        #expect(oldRatio < 3.0, "#52E39B reused as dark's marker pill fill must stay a documented failure — this is why dark inverts fill/label instead of reusing light's pairing.")
    }

    // 3. dark StatusChip labels: literal white on dark `success` (#52E39B) measures 1.64:1 and
    //    fails; the `onDanger` TOKEN on the same fill measures 11.32:1 and passes handily. Pins
    //    that the shipped code path (theme.colors.onDanger, per StatusChip.swift) is the one that
    //    passes — a regression back to a literal `Color.white` would be silently plausible-looking
    //    without this guard.
    @Test func darkStatusChipOnlineLabel_tokenPasses_literalWhiteWouldHaveFailed() {
        let tokenRatio = WCAGContrast.ratio(Theme.dark.colors.onDanger, Theme.dark.colors.success)
        #expect(abs(tokenRatio - 11.32) < 0.01, "dark `onDanger` (StatusChip.online's actual label token) vs dark `success` drifted off its documented 11.32:1.")
        #expect(tokenRatio >= 4.5)

        let literalWhiteRatio = WCAGContrast.ratio(.white, Theme.dark.colors.success)
        #expect(abs(literalWhiteRatio - 1.64) < 0.01, "the literal-white-on-dark-success ratio drifted off its documented (and known-failing) 1.64:1.")
        #expect(literalWhiteRatio < 4.5, "literal white on dark `success` must stay a documented failure — StatusChip.swift must read `theme.colors.onDanger`, never `Color.white`.")
    }

    // 4. light `outlineStrong` is 4.21:1 (vs `surface`) / 3.71:1 (vs `surfaceVariant`), not the
    //    "3.4:1-class" HANDOFF.md claimed (understated, not overstated, but still wrong — pin the
    //    real numbers rather than restating the vague claim).
    @Test func lightOutlineStrong_pinnedRealNumbers_notTheHandoffsVagueClaim() {
        let vsSurface = WCAGContrast.ratio(Theme.light.outlineStrong, Theme.light.colors.surface)
        let vsSurfaceVariant = WCAGContrast.ratio(Theme.light.outlineStrong, Theme.light.colors.surfaceVariant)
        #expect(abs(vsSurface - 4.21) < 0.01, "light `outlineStrong`/`surface` drifted off its documented 4.21:1 (specs/004 §2.1, corrected from HANDOFF.md's understated '3.4:1-class').")
        #expect(abs(vsSurfaceVariant - 3.71) < 0.01, "light `outlineStrong`/`surfaceVariant` drifted off its documented 3.71:1.")
        #expect(vsSurface >= 3.0 && vsSurfaceVariant >= 3.0)
    }

    // MARK: - Disabled-state tokens: documented values, not thresholds (I29 task item 3)
    //
    // WCAG 2.1 exempts inactive/disabled user-interface components from contrast requirements
    // (SC 1.4.3's own scope: "Incidental" text and "inactive" UI components are excluded). Both
    // `findlyDisabledLabel` (FindlyButton) and `findlyTextFieldDisabledText` measure BELOW 4.5:1
    // against the fills they're drawn on in light mode — that's legal for a disabled control and
    // must not be "fixed" by strengthening the color or asserting a threshold that would force a
    // stronger-than-necessary disabled state. Pinned as documented values instead, per
    // ColorTokens.swift's own comment on these tokens.
    @Test func disabledTokens_pinnedDocumentedValues_notThresholdGated() {
        let buttonDisabledLight = WCAGContrast.ratio(Color.findlyDisabledLabel, Theme.light.colors.surfaceVariant)
        let buttonDisabledDark = WCAGContrast.ratio(Color.findlyDisabledLabel, Theme.dark.colors.surfaceVariant)
        let textFieldDisabled = WCAGContrast.ratio(Color.findlyTextFieldDisabledText, Color.findlyTextFieldDisabledFill)

        #expect(abs(buttonDisabledLight - 2.45) < 0.01, "FindlyButton disabled label vs light `surfaceVariant` drifted off its documented 2.45:1 (below 4.5 — legal, disabled controls are WCAG-exempt).")
        #expect(abs(buttonDisabledDark - 5.48) < 0.01, "FindlyButton disabled label vs dark `surfaceVariant` drifted off its documented 5.48:1.")
        #expect(abs(textFieldDisabled - 2.54) < 0.01, "FindlyTextField disabled text vs its disabled fill drifted off its documented 2.54:1 (below 4.5 — legal, disabled controls are WCAG-exempt).")
    }
}
