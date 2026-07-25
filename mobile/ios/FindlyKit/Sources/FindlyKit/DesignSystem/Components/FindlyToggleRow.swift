import SwiftUI

/// specs/004-ios-client.md §2.3 (I2 addition) — a label(+subtitle) row with a trailing themed
/// toggle switch (device pause/`trackingEnabled`, geofence `notifyOnEnter`/`notifyOnExit`).
/// Stateless: takes a `Binding<Bool>`, reads `\.theme` only.
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
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurface.opacity(0.7))
                }
            }
            Spacer(minLength: theme.spacing.sm)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.colors.primary)
        }
        .padding(theme.spacing.md)
        .background(theme.colors.surface)
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
