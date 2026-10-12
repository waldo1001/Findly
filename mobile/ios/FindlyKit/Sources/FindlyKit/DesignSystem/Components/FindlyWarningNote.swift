import SwiftUI

/// specs/004-ios-client.md §2.3 (D21 addition, 2026-10-12) — an inline warning note: an optional
/// bold `lead` sentence followed by `body`, on a tinted `warning`-token surface. Plain strings only
/// (no markup); mirrors Android's `FindlyWarningNote` (003 §4.3). First use: the 005 §2.5 item-2
/// no-end-date warning. Reads `\.theme` only — corner radius and colours are tokens.
public struct FindlyWarningNote: View {
    @Environment(\.theme) private var theme
    private let lead: String?
    private let message: String

    public init(lead: String? = nil, body: String) {
        self.lead = lead
        self.message = body
    }

    public var body: some View {
        text
            .font(theme.typography.bodyMedium.font)
            .foregroundColor(theme.colors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.md)
            .background(theme.colors.warning.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: theme.corner.sm))
            .accessibilityElement(children: .combine)
    }

    private var text: Text {
        guard let lead else { return Text(message) }
        return Text(lead).bold() + Text(" " + message)
    }
}

#Preview("FindlyWarningNote — light") {
    FindlyWarningNote(lead: "This group has no end date.", body: "Everyone in it keeps seeing each other's live location.")
        .padding()
        .background(Theme.light.colors.surface)
        .environment(\.theme, .light)
}

#Preview("FindlyWarningNote — dark") {
    FindlyWarningNote(lead: "This group has no end date.", body: "Everyone in it keeps seeing each other's live location.")
        .padding()
        .background(Theme.dark.colors.surface)
        .environment(\.theme, .dark)
        .preferredColorScheme(.dark)
}
