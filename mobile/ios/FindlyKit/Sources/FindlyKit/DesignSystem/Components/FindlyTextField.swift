import SwiftUI

/// specs/004-ios-client.md §2.3 (I2 addition) — a labeled single-line text input used by the
/// invite/geofence-editor/settings forms. Stateless: takes a `Binding<String>`, reads `\.theme`
/// only. No literal `Color(...)`/`.font(.system(`/hardcoded point size.
public struct FindlyTextField: View {
    @Environment(\.theme) private var theme
    private let label: String
    @Binding private var text: String
    private let placeholder: String

    public init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(label)
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurface.opacity(0.7))
            TextField(placeholder, text: $text)
                .font(theme.typography.bodyLarge)
                .foregroundColor(theme.colors.onSurface)
                .padding(theme.spacing.sm)
                .background(theme.colors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: theme.corner.md))
        }
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
