import SwiftUI
@testable import FindlyKit

/// I29 (specs/004-ios-client §2.1) — the token pairings the design contract's own contrast claims
/// depend on, encoded as data so adding one is a data edit, not new test code (see
/// `ColorContrastPairingsTests.swift` for the assertions that walk this table).
///
/// **Cross-platform parity is the point (I29 task description).** Android's A28 asserts the same
/// pairings against `mobile/android/.../ui/designsystem/token/`. The `name` strings below are
/// written to line up with Android's table at a glance — a human diffing the two files by `name`
/// should see the same list, same order, same grouping (text-at-4.5 / strokes-at-3 /
/// components-at-4.5 / documented-exemptions). Any pairing legal on one platform and missing here
/// (or vice versa) is exactly the drift this test exists to prevent — flag it, don't silently add
/// or drop one side.
enum ColorContrastPairings {

    enum Scheme: String { case light, dark }

    struct TextOrStrokePairing {
        let name: String
        let scheme: Scheme
        let foreground: Color
        /// 1.0 (fully opaque) unless the real call site draws the foreground with `.opacity()` —
        /// e.g. `PermissionBannerView`'s message text. When < 1.0, the pairing is asserted by
        /// compositing `foreground` over `background` first (`WCAGContrast.ratio(foreground:alpha:
        /// background:)`), added I29 code-review round 2 MAJOR: `WCAGContrast.srgbComponents`
        /// never reads alpha on its own, so a translucent foreground asserted as if opaque would
        /// silently over-report its real, rendered contrast.
        let foregroundAlpha: Double
        let background: Color
        let threshold: Double

        init(name: String, scheme: Scheme, foreground: Color, foregroundAlpha: Double = 1.0, background: Color, threshold: Double) {
            self.name = name
            self.scheme = scheme
            self.foreground = foreground
            self.foregroundAlpha = foregroundAlpha
            self.background = background
            self.threshold = threshold
        }
    }

    // MARK: - Text at 4.5:1 (WCAG 2.1 SC 1.4.3, normal text)
    //
    // onPrimary/primary, onSurface/surface, onSurface/surfaceVariant, onDanger/danger, the
    // muted/subtle text color on both surface and surfaceVariant, and success/warning/danger used
    // as text directly on surface.
    static let textPairings: [TextOrStrokePairing] = {
        let light = Theme.light
        let dark = Theme.dark
        return [
            TextOrStrokePairing(name: "onPrimary/primary", scheme: .light, foreground: light.colors.onPrimary, background: light.colors.primary, threshold: 4.5),
            TextOrStrokePairing(name: "onPrimary/primary", scheme: .dark, foreground: dark.colors.onPrimary, background: dark.colors.primary, threshold: 4.5),

            TextOrStrokePairing(name: "onSurface/surface", scheme: .light, foreground: light.colors.onSurface, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "onSurface/surface", scheme: .dark, foreground: dark.colors.onSurface, background: dark.colors.surface, threshold: 4.5),

            TextOrStrokePairing(name: "onSurface/surfaceVariant", scheme: .light, foreground: light.colors.onSurface, background: light.colors.surfaceVariant, threshold: 4.5),
            TextOrStrokePairing(name: "onSurface/surfaceVariant", scheme: .dark, foreground: dark.colors.onSurface, background: dark.colors.surfaceVariant, threshold: 4.5),

            TextOrStrokePairing(name: "onDanger/danger", scheme: .light, foreground: light.colors.onDanger, background: light.colors.danger, threshold: 4.5),
            TextOrStrokePairing(name: "onDanger/danger", scheme: .dark, foreground: dark.colors.onDanger, background: dark.colors.danger, threshold: 4.5),

            TextOrStrokePairing(name: "mutedText/surface", scheme: .light, foreground: light.onSurfaceMuted, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "mutedText/surface", scheme: .dark, foreground: dark.onSurfaceMuted, background: dark.colors.surface, threshold: 4.5),

            TextOrStrokePairing(name: "mutedText/surfaceVariant", scheme: .light, foreground: light.onSurfaceMuted, background: light.colors.surfaceVariant, threshold: 4.5),
            TextOrStrokePairing(name: "mutedText/surfaceVariant", scheme: .dark, foreground: dark.onSurfaceMuted, background: dark.colors.surfaceVariant, threshold: 4.5),

            TextOrStrokePairing(name: "success-as-text/surface", scheme: .light, foreground: light.colors.success, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "success-as-text/surface", scheme: .dark, foreground: dark.colors.success, background: dark.colors.surface, threshold: 4.5),

            TextOrStrokePairing(name: "warning-as-text/surface", scheme: .light, foreground: light.colors.warning, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "warning-as-text/surface", scheme: .dark, foreground: dark.colors.warning, background: dark.colors.surface, threshold: 4.5),

            TextOrStrokePairing(name: "danger-as-text/surface", scheme: .light, foreground: light.colors.danger, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "danger-as-text/surface", scheme: .dark, foreground: dark.colors.danger, background: dark.colors.surface, threshold: 4.5),
        ]
    }()

    // MARK: - Meaningful strokes / graphical objects at 3:1 (WCAG 2.1 SC 1.4.11)
    //
    // outlineStrong against both surface and surfaceVariant; the marker pill fill against
    // primary; the paused-chip border against surface (StatusChip.swift: kind == .paused draws
    // `theme.outlineStrong` — same color as the first row, kept as its own named pairing because
    // it's a distinct claim about a distinct component, not a mathematical duplicate by accident).
    static let strokePairings: [TextOrStrokePairing] = {
        let light = Theme.light
        let dark = Theme.dark
        return [
            TextOrStrokePairing(name: "outlineStrong/surface", scheme: .light, foreground: light.outlineStrong, background: light.colors.surface, threshold: 3.0),
            TextOrStrokePairing(name: "outlineStrong/surface", scheme: .dark, foreground: dark.outlineStrong, background: dark.colors.surface, threshold: 3.0),

            TextOrStrokePairing(name: "outlineStrong/surfaceVariant", scheme: .light, foreground: light.outlineStrong, background: light.colors.surfaceVariant, threshold: 3.0),
            TextOrStrokePairing(name: "outlineStrong/surfaceVariant", scheme: .dark, foreground: dark.outlineStrong, background: dark.colors.surfaceVariant, threshold: 3.0),

            // MapMarkerBubble's "● NOW" badge fill (Theme.markerOnlineBadgeFill) against the pill's
            // own `primary` background — the badge must read as a distinct shape against the pill.
            TextOrStrokePairing(name: "markerPillFill/primary", scheme: .light, foreground: light.markerOnlineBadgeFill, background: light.colors.primary, threshold: 3.0),
            TextOrStrokePairing(name: "markerPillFill/primary", scheme: .dark, foreground: dark.markerOnlineBadgeFill, background: dark.colors.primary, threshold: 3.0),

            // StatusChip.swift: `.paused` has no fill (Color.clear) — its border (`outlineStrong`,
            // 1.5pt) is the row's whole status signal, rendered over whatever surface it sits on.
            TextOrStrokePairing(name: "pausedChipBorder/surface", scheme: .light, foreground: light.outlineStrong, background: light.colors.surface, threshold: 3.0),
            TextOrStrokePairing(name: "pausedChipBorder/surface", scheme: .dark, foreground: dark.outlineStrong, background: dark.colors.surface, threshold: 3.0),

            // FindlyTextField.swift borderColor: focused (`primary`) and error (`danger`) borders
            // against the field's own `surfaceVariant` fill — added I29 code-review round 2 MINOR.
            // This is literally the component's own doc comment's example of "an input outline is
            // exactly the 'carries meaning' case" for `outlineStrong` at rest; the focused/error
            // states swap to `primary`/`danger` and were untested.
            TextOrStrokePairing(name: "FindlyTextField focusedBorder/surfaceVariant", scheme: .light, foreground: light.colors.primary, background: light.colors.surfaceVariant, threshold: 3.0),
            TextOrStrokePairing(name: "FindlyTextField focusedBorder/surfaceVariant", scheme: .dark, foreground: dark.colors.primary, background: dark.colors.surfaceVariant, threshold: 3.0),

            TextOrStrokePairing(name: "FindlyTextField errorBorder/surfaceVariant", scheme: .light, foreground: light.colors.danger, background: light.colors.surfaceVariant, threshold: 3.0),
            TextOrStrokePairing(name: "FindlyTextField errorBorder/surfaceVariant", scheme: .dark, foreground: dark.colors.danger, background: dark.colors.surfaceVariant, threshold: 3.0),

            // PermissionBannerView.swift: the severity stripe (`Rectangle().fill(banner ==
            // .cannotReport ? theme.colors.danger : theme.colors.primary)`) over the banner's own
            // `surfaceVariant` fill — added I29 code-review round 3 MINOR 4. Numerically identical
            // to "FindlyTextField errorBorder/surfaceVariant" (danger) and
            // "FindlyTextField focusedBorder/surfaceVariant" (primary) respectively — same
            // "named for a distinct real UI element, not deduped away" convention as
            // "pausedChipBorder/surface" vs "outlineStrong/surface".
            TextOrStrokePairing(name: "PermissionBannerView stripe(cannotReport)/surfaceVariant", scheme: .light, foreground: light.colors.danger, background: light.colors.surfaceVariant, threshold: 3.0),
            TextOrStrokePairing(name: "PermissionBannerView stripe(cannotReport)/surfaceVariant", scheme: .dark, foreground: dark.colors.danger, background: dark.colors.surfaceVariant, threshold: 3.0),

            TextOrStrokePairing(name: "PermissionBannerView stripe(foregroundOnly)/surfaceVariant", scheme: .light, foreground: light.colors.primary, background: light.colors.surfaceVariant, threshold: 3.0),
            TextOrStrokePairing(name: "PermissionBannerView stripe(foregroundOnly)/surfaceVariant", scheme: .dark, foreground: dark.colors.primary, background: dark.colors.surfaceVariant, threshold: 3.0),
        ]
    }()

    // `secondary` (`ColorTokens.secondary`) is legitimately unasserted in every table on this page:
    // nothing in `Sources/FindlyKit/DesignSystem/Components` currently renders it (I29 code-review
    // round 2 finding, matched on Android's A28). Whoever wires it into a component MUST add a
    // pairing here in the same commit — this comment is the tripwire since the compiler can't
    // enforce "every token gets used, and used pairings get asserted" on its own.

    // MARK: - Component pairs at 4.5:1
    //
    // Every StatusChip kind's label on its own fill; the marker pill label on the pill fill.
    // (Disabled-state tokens are handled separately below — WCAG exempts disabled controls, so
    // they're documented-value pins, not threshold assertions.)
    static let componentPairings: [TextOrStrokePairing] = {
        let light = Theme.light
        let dark = Theme.dark
        return [
            // StatusChip.swift kind == .online: fill `success`, label `onDanger` (the TOKEN — see
            // the pinned dark-mode regression in ColorContrastPairingsTests for why not literal white).
            TextOrStrokePairing(name: "StatusChip.online label/fill", scheme: .light, foreground: light.colors.onDanger, background: light.colors.success, threshold: 4.5),
            TextOrStrokePairing(name: "StatusChip.online label/fill", scheme: .dark, foreground: dark.colors.onDanger, background: dark.colors.success, threshold: 4.5),

            // kind == .stale: fill `warning`, label `onDanger`.
            TextOrStrokePairing(name: "StatusChip.stale label/fill", scheme: .light, foreground: light.colors.onDanger, background: light.colors.warning, threshold: 4.5),
            TextOrStrokePairing(name: "StatusChip.stale label/fill", scheme: .dark, foreground: dark.colors.onDanger, background: dark.colors.warning, threshold: 4.5),

            // kind == .danger: fill `danger`, label `onDanger`.
            TextOrStrokePairing(name: "StatusChip.danger label/fill", scheme: .light, foreground: light.colors.onDanger, background: light.colors.danger, threshold: 4.5),
            TextOrStrokePairing(name: "StatusChip.danger label/fill", scheme: .dark, foreground: dark.colors.onDanger, background: dark.colors.danger, threshold: 4.5),

            // kind == .paused: no fill (Color.clear), label `onSurface` — evaluated against
            // `surface`, the app's base background the chip is always composited over.
            TextOrStrokePairing(name: "StatusChip.paused label/surface", scheme: .light, foreground: light.colors.onSurface, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "StatusChip.paused label/surface", scheme: .dark, foreground: dark.colors.onSurface, background: dark.colors.surface, threshold: 4.5),

            // MapMarkerBubble's "● NOW" badge label on its own fill (Theme.markerOnlineBadgeLabel/Fill).
            TextOrStrokePairing(name: "MarkerBadge label/fill", scheme: .light, foreground: light.markerOnlineBadgeLabel, background: light.markerOnlineBadgeFill, threshold: 4.5),
            TextOrStrokePairing(name: "MarkerBadge label/fill", scheme: .dark, foreground: dark.markerOnlineBadgeLabel, background: dark.markerOnlineBadgeFill, threshold: 4.5),

            // ErrorStateView.swift: the "▲" glyph renders in `warning` on the view's own
            // `surfaceVariant` fill (NOT `surface` — the handoff's "warning-as-text/surface" text
            // pairing above measures a different, higher-margin number than what actually renders
            // here). Added I29 code-review round 2 MAJOR: passes (light 4.76:1), but by a much
            // thinner margin (+0.26) than the untested `surface` figure (+0.89) would suggest.
            TextOrStrokePairing(name: "ErrorStateView warningGlyph/surfaceVariant", scheme: .light, foreground: light.colors.warning, background: light.colors.surfaceVariant, threshold: 4.5),
            TextOrStrokePairing(name: "ErrorStateView warningGlyph/surfaceVariant", scheme: .dark, foreground: dark.colors.warning, background: dark.colors.surfaceVariant, threshold: 4.5),

            // PermissionBannerView.swift: the message text is `onSurface` at 0.75 alpha over the
            // banner's `surfaceVariant` fill — added I29 code-review round 2 MAJOR (the dismiss
            // icon alongside it, originally `onSurface.opacity(0.6)`, was a LIVE AA failure at
            // 4.43:1 light; fixed in Sources to use `onSurfaceMuted` instead of an ad-hoc opacity —
            // see PermissionBannerView.swift and the pairing right below this one).
            TextOrStrokePairing(name: "PermissionBannerView message(0.75)/surfaceVariant", scheme: .light, foreground: light.colors.onSurface, foregroundAlpha: 0.75, background: light.colors.surfaceVariant, threshold: 4.5),
            TextOrStrokePairing(name: "PermissionBannerView message(0.75)/surfaceVariant", scheme: .dark, foreground: dark.colors.onSurface, foregroundAlpha: 0.75, background: dark.colors.surfaceVariant, threshold: 4.5),

            // The dismiss icon, post-fix: `onSurfaceMuted` (opaque, no ad-hoc opacity) — passes
            // with real margin instead of failing at 4.43:1. Numerically identical to
            // "mutedText/surfaceVariant" above; kept as its own named pairing (same convention as
            // "pausedChipBorder/surface") because it pins a specific real bug fix, not a duplicate
            // by accident.
            TextOrStrokePairing(name: "PermissionBannerView dismissIcon/surfaceVariant", scheme: .light, foreground: light.onSurfaceMuted, background: light.colors.surfaceVariant, threshold: 4.5),
            TextOrStrokePairing(name: "PermissionBannerView dismissIcon/surfaceVariant", scheme: .dark, foreground: dark.onSurfaceMuted, background: dark.colors.surfaceVariant, threshold: 4.5),

            // FindlyNavBar.swift (back chevron, trailing text action) and LoadingStateView.swift
            // (determinate progress tint) all draw `primary` directly on `surface` — one shared
            // color pairing across three call sites, added I29 code-review round 2 MINOR.
            TextOrStrokePairing(name: "primary icon-or-text/surface", scheme: .light, foreground: light.colors.primary, background: light.colors.surface, threshold: 4.5),
            TextOrStrokePairing(name: "primary icon-or-text/surface", scheme: .dark, foreground: dark.colors.primary, background: dark.colors.surface, threshold: 4.5),

            // FindlyTextField.swift: `Text("✕ \(errorMessage)")` renders in `danger` on the field's
            // `surfaceVariant` fill — this is BODY TEXT (WCAG 2.1 SC 1.4.3, 4.5:1), a different
            // claim from "FindlyTextField errorBorder/surfaceVariant" above, which is the 1.5pt
            // border stroke (SC 1.4.11, 3:1) and happens to share the same two colors. Added I29
            // code-review round 3 MINOR 2: same numbers as the border pairing (danger/
            // surfaceVariant), but was previously only asserted at the border's 3:1 threshold —
            // an untested claim held at the wrong bar, even though it clears 4.5 anyway.
            TextOrStrokePairing(name: "FindlyTextField errorMessage/surfaceVariant", scheme: .light, foreground: light.colors.danger, background: light.colors.surfaceVariant, threshold: 4.5),
            TextOrStrokePairing(name: "FindlyTextField errorMessage/surfaceVariant", scheme: .dark, foreground: dark.colors.danger, background: dark.colors.surfaceVariant, threshold: 4.5),
        ]
    }()
}
