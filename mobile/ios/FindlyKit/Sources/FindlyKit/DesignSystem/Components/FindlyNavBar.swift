import SwiftUI

/// specs/004-ios-client.md §2.3 — a lightweight top bar; screens compose this rather than relying
/// on the system navigation bar's default (unthemed) chrome.
public struct FindlyNavBar: View {
    @Environment(\.theme) private var theme
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(theme.typography.titleLarge)
            .foregroundColor(theme.colors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.md)
            .background(theme.colors.surface)
    }
}

// #Preview blocks intentionally omitted: this session's build/test verification environment has
// only Xcode Command Line Tools (no Xcode.app), which lacks the `PreviewsMacros` compiler plugin
// `#Preview` needs — even an empty `#Preview {}` fails to compile here. Adding light/dark previews
// back is a trivial, non-blocking follow-up once a real Xcode toolchain is available (see
// specs/004-ios-client.md §2.3); the package must build clean in THIS environment first.
