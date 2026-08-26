import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §5.1 item 1 ("titleLarge-class size, tabular figures,
/// letter-spaced, in hyphenated display form") — a small presentational component so the invite
/// code's styling lives in `DesignSystem/`, not hand-rolled at `CreateInviteScreen`'s call site.
/// Named `FindlyCodeDisplay` (review fix, I37 round 2), matching Android's independently-chosen
/// name for its own twin — every 010-batch component is `Findly*` on both platforms
/// (`FindlyNavDrawer`, `FindlyBottomSheet`, `FindlyDropdownField`); iOS's unprefixed components
/// (`StatusChip`, `MapMarkerBubble`, `EmptyStateView`) all predate this batch.
///
/// 004 §2.3's "zero styling outside DesignSystem/" rule scopes to `Screens/`, view models,
/// navigation, and networking — NOT to design-system components themselves, which are exactly
/// where presentational literals belong (`StatusChip`'s own `.tracking(0.3)` on its uppercase
/// label is the existing iOS precedent; Android's `FindlyMapMarkerBubble.kt` local `TextStyle`
/// literals are the cross-platform one). This component still reads `\.theme` only and derives
/// `titleLarge` rather than inventing a new typography token — `theme.typography.titleLarge.font`
/// supplies size/weight, `.monospacedDigit()` gives the tabular-figure alignment a code needs so
/// digits don't jitter width as they change, and an additional literal `.tracking(_:)` widens the
/// letter-spacing beyond what `titleLarge.tracking` alone provides (that token's own -0.2 is a
/// headline *tightening*, correct for a title, wrong for a code meant to read as visually
/// separated characters).
public struct FindlyCodeDisplay: View {
    @Environment(\.theme) private var theme
    private let displayForm: String

    /// [displayForm] is expected to already be the hyphenated `XXXX-XXXX` form (e.g.
    /// `CreateInviteViewModel.displayForm(for:)`) — this component renders whatever string it's
    /// given, with zero knowledge of the Crockford base32 code format itself.
    public init(_ displayForm: String) {
        self.displayForm = displayForm
    }

    public var body: some View {
        Text(displayForm)
            .font(theme.typography.titleLarge.font)
            .monospacedDigit()
            .tracking(2)
            .foregroundColor(theme.colors.onSurface)
            .accessibilityLabel("Invite code \(displayForm)")
    }
}

#Preview("FindlyCodeDisplay — light") {
    FindlyCodeDisplay("7F3K-9QRZ")
        .padding()
        .background(Theme.light.colors.surface)
        .environment(\.theme, .light)
}

#Preview("FindlyCodeDisplay — dark") {
    FindlyCodeDisplay("7F3K-9QRZ")
        .padding()
        .background(Theme.dark.colors.surface)
        .environment(\.theme, .dark)
        .preferredColorScheme(.dark)
}
