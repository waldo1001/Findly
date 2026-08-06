import SwiftUI

/// specs/004-ios-client.md §2.3 (I2 addition) — a label(+subtitle) row with a trailing themed
/// toggle switch (device pause/`trackingEnabled`, geofence `notifyOnEnter`/`notifyOnExit`).
/// Stateless: takes a `Binding<Bool>`, reads `\.theme` only.
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md) draws a custom
/// 52×32 track in the mock purely to show the on/off colours — the handoff is explicit that iOS
/// uses the **native** `Toggle`/`UISwitch` (not a hand-drawn track), which this already does;
/// I27 only restyles the label/spacing around it. `.tint` gives the native control `primary` as
/// its "on" color, matching the mock's intent as closely as the native component allows.
public struct FindlyToggleRow: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    public init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.colors.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.bodyMedium.font)
                        .foregroundColor(theme.onSurfaceMuted)
                }
            }
            Spacer(minLength: theme.spacing.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.colors.primary)
        }
        .padding(.horizontal, theme.spacing.md)
        .frame(minHeight: 56)
        .background(theme.colors.surface)
    }
}

#Preview("FindlyToggleRow — light") {
    VStack(spacing: 0) {
        FindlyToggleRow(title: "Noor's iPhone", subtitle: "Syncing every 5 min · battery 82%", isOn: .constant(true))
        FindlyCardDivider()
        FindlyToggleRow(title: "Lina's iPad", subtitle: "No location yet — waiting for first check-in", isOn: .constant(false))
    }
    .padding()
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyToggleRow — dark") {
    VStack(spacing: 0) {
        FindlyToggleRow(title: "Noor's iPhone", subtitle: "Syncing every 5 min · battery 82%", isOn: .constant(true))
        FindlyCardDivider()
        FindlyToggleRow(title: "Lina's iPad", subtitle: "No location yet — waiting for first check-in", isOn: .constant(false))
    }
    .padding()
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
