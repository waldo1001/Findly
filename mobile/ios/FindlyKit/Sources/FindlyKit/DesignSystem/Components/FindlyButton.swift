import SwiftUI

/// specs/004-ios-client.md §2.3 — stateless, presentational. Reads `\.theme` only; takes content
/// via parameters. Zero knowledge of view models/networking/navigation.
public enum FindlyButtonStyleKind: Equatable {
    case primary
    case secondary
}

public struct FindlyButton: View {
    @Environment(\.theme) private var theme
    private let title: String
    private let style: FindlyButtonStyleKind
    private let action: () -> Void

    public init(_ title: String, style: FindlyButtonStyleKind = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.typography.titleMedium)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.vertical, theme.spacing.sm)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: theme.corner.md))
        }
    }

    private var backgroundColor: Color {
        style == .primary ? theme.colors.primary : theme.colors.surfaceVariant
    }

    private var foregroundColor: Color {
        style == .primary ? theme.colors.onPrimary : theme.colors.onSurface
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
