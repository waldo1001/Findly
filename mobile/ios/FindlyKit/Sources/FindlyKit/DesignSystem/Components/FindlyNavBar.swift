import SwiftUI

/// specs/004-ios-client.md §2.5 — how the *one* central back action reaches the *many* nav bars.
///
/// Every screen already renders its own `FindlyNavBar(title)`. Rendering a second, separate back
/// bar in `RootView` would double the chrome, and threading an `onBack` parameter through all 20
/// screens would put the "should there be a back button here?" decision back in each screen — the
/// exact mistake §2.5 exists to prevent. So `RootView` publishes the decision once, into the
/// environment, and the design-system component consumes it. Screens stay untouched and cannot get
/// it wrong.
public struct NavBarBackActionKey: EnvironmentKey {
    public static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
    /// Non-nil exactly when `AppCoordinator.canGoBack` is true.
    var navBarBackAction: (() -> Void)? {
        get { self[NavBarBackActionKey.self] }
        set { self[NavBarBackActionKey.self] = newValue }
    }
}

/// specs/004-ios-client.md §2.3 — a lightweight top bar; screens compose this rather than relying
/// on the system navigation bar's default (unthemed) chrome.
public struct FindlyNavBar: View {
    @Environment(\.theme) private var theme
    /// specs/004 §2.5 — the central back action, published once by `RootView`. Screens do NOT
    /// supply this; a per-screen back button is exactly what left 20 screens with 20 different
    /// (or absent) answers and no way out of most of them.
    @Environment(\.navBarBackAction) private var environmentBackAction
    private let title: String
    /// Explicit override, for the rare bar that is not the screen's navigation root (and for
    /// previews/tests). When nil — the normal case — the environment action is used.
    private let onBack: (() -> Void)?

    public init(_ title: String, onBack: (() -> Void)? = nil) {
        self.title = title
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: theme.spacing.sm) {
            if let onBack = onBack ?? environmentBackAction {
                Button(action: onBack) {
                    // SF Symbol, not a literal glyph: it mirrors for right-to-left layouts and
                    // scales with Dynamic Type automatically.
                    Image(systemName: "chevron.backward")
                        .font(theme.typography.titleMedium)
                        .foregroundColor(theme.colors.primary)
                        // A bare chevron is a small tap target. Pad with tokens (§2.1 forbids
                        // hardcoded point sizes here) and make the whole padded area — not just
                        // the glyph's own bounds — hit-testable.
                        .padding(.vertical, theme.spacing.xs)
                        .padding(.trailing, theme.spacing.sm)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            }

            Text(title)
                .font(theme.typography.titleLarge)
                .foregroundColor(theme.colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
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
