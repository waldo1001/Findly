import SwiftUI

/// specs/004-ios-client.md §2.3 — a section label (e.g. "MEMBERS", "DEVICES" on Family & devices).
/// New in I27: design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md) is
/// the first handoff to specify this as its own named component rather than ad hoc screen text.
///
/// `labelSmall`, uppercase, muted, 4pt horizontal padding (== `SpacingTokens.xs`). The handoff's
/// "10pt below the previous block" is spacing between this header and whatever precedes it in a
/// screen's layout — a caller concern (`Screens/`, I28), not something this stateless component
/// can apply to itself.
public struct FindlySectionHeader: View {
    @Environment(\.theme) private var theme
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(theme.typography.labelSmall.font)
            .tracking(theme.typography.labelSmall.tracking)
            .textCase(.uppercase)
            .foregroundColor(theme.onSurfaceMuted)
            .padding(.horizontal, theme.spacing.xs)
    }
}

#Preview("FindlySectionHeader — light") {
    VStack(alignment: .leading, spacing: 8) {
        FindlySectionHeader("Members")
        FindlySectionHeader("Devices")
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlySectionHeader — dark") {
    VStack(alignment: .leading, spacing: 8) {
        FindlySectionHeader("Members")
        FindlySectionHeader("Devices")
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
