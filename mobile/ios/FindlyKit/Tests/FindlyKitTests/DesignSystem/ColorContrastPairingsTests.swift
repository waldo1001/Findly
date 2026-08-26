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
        #expect(
            Self.passes(pairing),
            """
            "\(pairing.name)" (\(pairing.scheme.rawValue)) measures \(Self.ratio(for: pairing)):1, \
            below the \(pairing.threshold):1 text threshold (WCAG 2.1 SC 1.4.3). If this is one of \
            the four known-bad handoff numbers, it should already be fixed at the token level — \
            see ColorContrastPairingsTests's pinned-regression tests. If this is a NEW failure, \
            stop and report rather than adjusting the threshold or the color (I29 task instructions).
            """
        )
    }

    // MARK: - Meaningful strokes / graphical objects at 3:1

    @Test(arguments: ColorContrastPairings.strokePairings)
    func strokePairing_meetsWCAG_3_0(_ pairing: ColorContrastPairings.TextOrStrokePairing) {
        #expect(
            Self.passes(pairing),
            """
            "\(pairing.name)" (\(pairing.scheme.rawValue)) measures \(Self.ratio(for: pairing)):1, \
            below the \(pairing.threshold):1 meaningful-stroke threshold (WCAG 2.1 SC 1.4.11). \
            Stop and report rather than adjusting the threshold or the color if this is unexpected.
            """
        )
    }

    // MARK: - Component pairs at 4.5:1

    @Test(arguments: ColorContrastPairings.componentPairings)
    func componentPairing_meetsWCAG_4_5(_ pairing: ColorContrastPairings.TextOrStrokePairing) {
        #expect(
            Self.passes(pairing),
            """
            "\(pairing.name)" (\(pairing.scheme.rawValue)) measures \(Self.ratio(for: pairing)):1, \
            below the \(pairing.threshold):1 component threshold (WCAG 2.1 SC 1.4.3). Stop and \
            report rather than adjusting the threshold or the color if this is unexpected.
            """
        )
    }

    /// Routes a pairing through the alpha-compositing formula when it carries a translucent
    /// foreground (`foregroundAlpha < 1.0` — e.g. `PermissionBannerView`'s message text), and the
    /// plain opaque formula otherwise. Added I29 code-review round 2 MAJOR alongside
    /// `WCAGContrast.ratio(foreground:alpha:background:)`.
    private static func ratio(for pairing: ColorContrastPairings.TextOrStrokePairing) -> Double {
        pairing.foregroundAlpha < 1.0
            ? WCAGContrast.ratio(foreground: pairing.foreground, alpha: pairing.foregroundAlpha, background: pairing.background)
            : WCAGContrast.ratio(pairing.foreground, pairing.background)
    }

    /// The single comparison every real pairing test above goes through — added I29 code-review
    /// round 3 MINOR 1: the three `@Test(arguments:)` functions previously inlined their own
    /// `ratio >= pairing.threshold` separately, so `syntheticFailingPairing_provesDetectionStaysLive`
    /// (computing `WCAGContrast.ratio(.black, .black)` standalone) shared only the low-level
    /// formula with them, not this comparison — an inverted `>=` inside any one of the three loops
    /// would have sailed past it undetected. Now all three loops AND the synthetic control call
    /// this one function, so a broken (or vacuous, e.g. hardcoded `true`) comparison here breaks
    /// the synthetic control too, regardless of which call site it was "fixed" in.
    private static func passes(_ pairing: ColorContrastPairings.TextOrStrokePairing) -> Bool {
        ratio(for: pairing) >= pairing.threshold
    }

    // MARK: - A31/I31: exact-color pins for every declared pairing, not just its WCAG floor
    //
    // The three loops above only prove a pairing clears >= 4.5/3.0 — that is necessary but not
    // sufficient. I30's `onSurfaceMuted` correction is the reason this exists: light `onSurface`
    // at ~70% measured 6.56:1, comfortably cleared the 4.5:1 floor, and was therefore structurally
    // invisible to a floor-only check — the same real-device report that produced Android's A30.
    // `DesignTokens2aTests.swift` already pins the exact hex of every *token* this file reads
    // (`ColorTokens.light/dark`, `Theme.outlineStrong`, `Theme.onSurfaceMuted`,
    // `Theme.markerOnlineBadgeFill/Label`) — so a token edit already fails a test elsewhere. This
    // test pins the same exact values again, but keyed to the *declared pairing* itself (the same
    // object Android's A31 exact-ratio table pins), so an entry here is a direct, per-pairing
    // record of "this named pairing is built from exactly these colors" — catching a future
    // pairing declaration that reads the wrong token or an inlined literal instead of the named
    // one, which a token-level-only pin could never see. iOS's "stronger" exact-hex form (per the
    // A31 task description) fixes the colour itself rather than a derived ratio, so any drift —
    // even one that would still clear AA — fails immediately.
    //
    // **Deliberately bare `Color(hex:)` literals below, never `ColorTokens.light`/`Theme.light`
    // accessors.** Comparing a pairing's live color against the SAME live accessor it was built
    // from is a no-op tautology — it would pass no matter what the token was changed to, since
    // both sides read the identical source. The whole point of a pin is an independent, frozen
    // expectation that does not move when the token does.
    @Test func declaredPairings_pinExactColorsAndAlpha_notJustWCAGFloor() {
        struct Pin {
            let foreground: Color
            let foregroundAlpha: Double
            let background: Color
        }

        func pin(_ fgHex: UInt32, _ bgHex: UInt32, alpha: Double = 1.0) -> Pin {
            Pin(foreground: Color(hex: fgHex), foregroundAlpha: alpha, background: Color(hex: bgHex))
        }

        let expected: [String: [ColorContrastPairings.Scheme: Pin]] = [
            // --- text pairings ---
            "onPrimary/primary": [.light: pin(0xFFFFFF, 0x3A46C8), .dark: pin(0x0A0F27, 0x7C8BFF)],
            "onSurface/surface": [.light: pin(0x10142A, 0xF2F4FB), .dark: pin(0xE8ECF7, 0x0B0F1C)],
            "onSurface/surfaceVariant": [.light: pin(0x10142A, 0xE2E6F5), .dark: pin(0xE8ECF7, 0x161D33)],
            "onDanger/danger": [.light: pin(0xFFFFFF, 0xB3261E), .dark: pin(0x2A0708, 0xFF6B6B)],
            "mutedText/surface": [.light: pin(0x3A4160, 0xF2F4FB), .dark: pin(0x98A1BD, 0x0B0F1C)],
            "mutedText/surfaceVariant": [.light: pin(0x3A4160, 0xE2E6F5), .dark: pin(0x98A1BD, 0x161D33)],
            "success-as-text/surface": [.light: pin(0x10714A, 0xF2F4FB), .dark: pin(0x52E39B, 0x0B0F1C)],
            "warning-as-text/surface": [.light: pin(0x8A5A00, 0xF2F4FB), .dark: pin(0xFFC44D, 0x0B0F1C)],
            "danger-as-text/surface": [.light: pin(0xB3261E, 0xF2F4FB), .dark: pin(0xFF6B6B, 0x0B0F1C)],

            // --- stroke pairings ---
            "outlineStrong/surface": [.light: pin(0x6B739A, 0xF2F4FB), .dark: pin(0x6B739A, 0x0B0F1C)],
            "outlineStrong/surfaceVariant": [.light: pin(0x6B739A, 0xE2E6F5), .dark: pin(0x6B739A, 0x161D33)],
            "markerPillFill/primary": [.light: pin(0x52E39B, 0x3A46C8), .dark: pin(0x0B3B26, 0x7C8BFF)],
            "pausedChipBorder/surface": [.light: pin(0x6B739A, 0xF2F4FB), .dark: pin(0x6B739A, 0x0B0F1C)],
            "FindlyTextField focusedBorder/surfaceVariant": [.light: pin(0x3A46C8, 0xE2E6F5), .dark: pin(0x7C8BFF, 0x161D33)],
            "FindlyTextField errorBorder/surfaceVariant": [.light: pin(0xB3261E, 0xE2E6F5), .dark: pin(0xFF6B6B, 0x161D33)],
            "PermissionBannerView stripe(cannotReport)/surfaceVariant": [.light: pin(0xB3261E, 0xE2E6F5), .dark: pin(0xFF6B6B, 0x161D33)],
            "PermissionBannerView stripe(foregroundOnly)/surfaceVariant": [.light: pin(0x3A46C8, 0xE2E6F5), .dark: pin(0x7C8BFF, 0x161D33)],

            // --- component pairings ---
            "StatusChip.online label/fill": [.light: pin(0xFFFFFF, 0x10714A), .dark: pin(0x2A0708, 0x52E39B)],
            "StatusChip.stale label/fill": [.light: pin(0xFFFFFF, 0x8A5A00), .dark: pin(0x2A0708, 0xFFC44D)],
            "StatusChip.danger label/fill": [.light: pin(0xFFFFFF, 0xB3261E), .dark: pin(0x2A0708, 0xFF6B6B)],
            "StatusChip.paused label/surface": [.light: pin(0x10142A, 0xF2F4FB), .dark: pin(0xE8ECF7, 0x0B0F1C)],
            "MarkerBadge label/fill": [.light: pin(0x062418, 0x52E39B), .dark: pin(0x52E39B, 0x0B3B26)],
            "ErrorStateView warningGlyph/surfaceVariant": [.light: pin(0x8A5A00, 0xE2E6F5), .dark: pin(0xFFC44D, 0x161D33)],
            "PermissionBannerView message(0.75)/surfaceVariant": [
                .light: pin(0x10142A, 0xE2E6F5, alpha: 0.75),
                .dark: pin(0xE8ECF7, 0x161D33, alpha: 0.75),
            ],
            "PermissionDisclosureScreen closing(0.75)/surfaceVariant": [
                .light: pin(0x10142A, 0xE2E6F5, alpha: 0.75),
                .dark: pin(0xE8ECF7, 0x161D33, alpha: 0.75),
            ],
            "PermissionBannerView dismissIcon/surfaceVariant": [.light: pin(0x3A4160, 0xE2E6F5), .dark: pin(0x98A1BD, 0x161D33)],
            "primary icon-or-text/surface": [.light: pin(0x3A46C8, 0xF2F4FB), .dark: pin(0x7C8BFF, 0x0B0F1C)],
            "FindlyTextField errorMessage/surfaceVariant": [.light: pin(0xB3261E, 0xE2E6F5), .dark: pin(0xFF6B6B, 0x161D33)],
        ]

        let all = ColorContrastPairings.textPairings + ColorContrastPairings.strokePairings + ColorContrastPairings.componentPairings

        let mismatches: [String] = all.compactMap { pairing in
            guard let want = expected[pairing.name]?[pairing.scheme] else {
                return "\(pairing.name) (\(pairing.scheme.rawValue)): no A31/I31 exact pin registered — every declared pairing must have one"
            }
            if pairing.foreground != want.foreground || pairing.background != want.background || pairing.foregroundAlpha != want.foregroundAlpha {
                return "\(pairing.name) (\(pairing.scheme.rawValue)): foreground/background/alpha drifted from its A31/I31 pin"
            }
            return nil
        }

        #expect(
            mismatches.isEmpty,
            """
            One or more declared pairings drifted from their A31/I31 exact-color pin, or have no \
            pin registered at all. Clearing the WCAG floor above is not sufficient evidence a \
            change was intentional or correct — that is the exact gap I30's onSurfaceMuted fix \
            closed for one token. If this is a deliberate token change, update `expected` above \
            in the same commit:
            \(mismatches.joined(separator: "\n"))
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

    // MARK: - `secondary` exemption, pinned numerically (I29 code-review round 3 MINOR 3)
    //
    // `ColorTokens.secondary` is unasserted everywhere else on this page because nothing in
    // `Sources/FindlyKit/DesignSystem/Components` currently renders it (see the comment above
    // `strokePairings`). That's a comment-only claim on its own — pinned here so drift shows up in
    // a diff instead of someone's memory. At its CURRENT value, `secondary` cannot carry text on
    // EITHER light surface: both measure below the 4.5:1 text threshold. Whoever wires `secondary`
    // into a component text role must fix the color first, not just add a pairing that documents
    // the failure.
    @Test func secondaryToken_light_cannotCarryTextOnEitherSurface_pinnedExemption() {
        let onSurface = WCAGContrast.ratio(Theme.light.colors.secondary, Theme.light.colors.surface)
        let onSurfaceVariant = WCAGContrast.ratio(Theme.light.colors.secondary, Theme.light.colors.surfaceVariant)
        #expect(abs(onSurface - 4.4456) < 0.001, "light `secondary`/`surface` drifted off its documented 4.4456:1.")
        #expect(abs(onSurfaceVariant - 3.9250) < 0.001, "light `secondary`/`surfaceVariant` drifted off its documented 3.9250:1.")
        #expect(onSurface < 4.5, "light `secondary` on `surface` must stay below 4.5:1 — it cannot carry text there today. If this ever passes, the exemption comment above is stale, not a reason to delete this test.")
        #expect(onSurfaceVariant < 4.5, "light `secondary` on `surfaceVariant` must stay below 4.5:1 — same reasoning.")
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
        #expect(abs(outlineStrongRatio - 4.13) < 0.01, "dark `outlineStrong`/`surface` drifted off its documented 4.13:1 (I29 code-review round 2 MINOR — was only threshold-checked before, not pinned to the exact number the way light's is).")
        #expect(outlineStrongRatio >= 3.0, "`outlineStrong` (the correct token for meaningful strokes in dark) must pass 3:1 where raw `outline` fails.")

        let outlineStrongVsSurfaceVariantRatio = WCAGContrast.ratio(Theme.dark.outlineStrong, Theme.dark.colors.surfaceVariant)
        #expect(abs(outlineStrongVsSurfaceVariantRatio - 3.61) < 0.01, "dark `outlineStrong`/`surfaceVariant` drifted off its documented 3.61:1.")
        #expect(outlineStrongVsSurfaceVariantRatio >= 3.0)
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

        // FindlyButton.swift foregroundColor: `.secondary`/`.destructive` styles composite their
        // disabled label over `Color.clear` — i.e. the ambient `surface` behind the button, NOT
        // `surfaceVariant` (that's only `.primary`'s disabled fill). Added I29 code-review round 2
        // MINOR — the `surfaceVariant` pin above only covers `.primary`.
        let buttonDisabledOnSurfaceLight = WCAGContrast.ratio(Color.findlyDisabledLabel, Theme.light.colors.surface)
        let buttonDisabledOnSurfaceDark = WCAGContrast.ratio(Color.findlyDisabledLabel, Theme.dark.colors.surface)
        #expect(abs(buttonDisabledOnSurfaceLight - 2.77) < 0.01, "FindlyButton .secondary/.destructive disabled label vs light `surface` (ambient, through Color.clear) drifted off its documented 2.77:1 (below 4.5 — legal, disabled controls are WCAG-exempt).")
        #expect(abs(buttonDisabledOnSurfaceDark - 6.27) < 0.01, "FindlyButton .secondary/.destructive disabled label vs dark `surface` drifted off its documented 6.27:1.")

        // FindlyTextField.swift borderColor: disabled border vs the field's own disabled fill —
        // the one disabled pair left unpinned (border-vs-fill, not label/text-vs-fill like the
        // three above). Added I29 code-review round 2 MINOR.
        let textFieldDisabledBorder = WCAGContrast.ratio(Color.findlyTextFieldDisabledBorder, Color.findlyTextFieldDisabledFill)
        #expect(abs(textFieldDisabledBorder - 1.19) < 0.01, "FindlyTextField disabled border vs its disabled fill drifted off its documented 1.19:1 (below 3.0 — legal, disabled controls are WCAG-exempt; a disabled border only needs to read as \"there's a field here\", not stand out).")
    }

    // MARK: - Synthetic negative control (I29 code-review round 2, adopted per the reviewer's
    // suggested pattern for proving detection stays live in the committed suite itself, rather
    // than by the uncommitted manual sabotage-and-revert step used during I29's first round;
    // corrected in round 3 MINOR 1 to sit ON the real assertion path, not beside it).
    //
    // Black on black is always 1:1 — always below any real threshold used on this page. Built as
    // an actual `TextOrStrokePairing` and run through `Self.passes(_:)` — the EXACT function every
    // real loop above asserts against — rather than calling `WCAGContrast.ratio` standalone. That
    // matters: a standalone call only proves the low-level formula still works: it would keep
    // passing even if someone inverted `>=` to `<=` inside one of the three `@Test(arguments:)`
    // functions, because those used to inline their own comparison rather than share this one.
    // Now they don't, so a broken comparison here fails BOTH the real loops (loudly, en masse) AND
    // this control (specifically, by design) — and if the comparison instead degenerated to
    // something vacuous like `true` (which would make every real loop pass silently, the actually
    // dangerous failure mode), this control is the one that would still catch it, because it
    // expects `passes` to return `false` and a vacuous `true` breaks exactly that expectation.
    @Test func syntheticFailingPairing_provesDetectionStaysLive() {
        let synthetic = ColorContrastPairings.TextOrStrokePairing(
            name: "SYNTHETIC negative control (expected to fail — do not fix)",
            scheme: .light,
            foreground: .black,
            background: .black,
            threshold: 4.5
        )
        #expect(abs(Self.ratio(for: synthetic) - 1.0) < 0.0001, "black-on-black must measure exactly 1:1 — the formula's own floor.")
        #expect(
            !Self.passes(synthetic),
            "black-on-black must stay a documented failure against `Self.passes(_:)` — the exact function every real pairing test in this file asserts against. This negative control exists to prove the suite can still detect a failing pairing, permanently, on the real assertion path, without needing an uncommitted manual step."
        )
    }
}
