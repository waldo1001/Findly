import SwiftUI

/// specs/004-ios-client.md §2.3 — the "nothing here yet" state (e.g. no devices, no geofences).
public struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: theme.spacing.sm) {
            Text(title)
                .font(theme.typography.titleMedium)
                .foregroundColor(theme.colors.onSurface)
            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.onSurface.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(theme.spacing.xl)
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
