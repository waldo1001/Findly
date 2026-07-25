import SwiftUI

/// specs/004-ios-client.md §2.3 — a generic elevated surface container. Shadow tint is derived
/// from `onSurface` (never a literal `.black`) so it adapts automatically between light/dark.
public struct FindlyCard<Content: View>: View {
    @Environment(\.theme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(theme.spacing.md)
            .background(theme.colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
            .shadow(
                color: theme.colors.onSurface.opacity(theme.elevation.level1.opacity),
                radius: theme.elevation.level1.radius,
                y: theme.elevation.level1.y
            )
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
