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
        let background: Color
        let threshold: Double
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
        ]
    }()

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
        ]
    }()
}
