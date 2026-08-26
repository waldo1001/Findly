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
///
/// design 2a "Ember/Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md): height 52, a
/// 44×44 back touch target around a 22pt chevron, title 18/600 at −0.2 tracking, and an optional
/// trailing text action (15/600, `primary`) — e.g. "Edit" on Family & devices.
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
    /// specs/010-app-shell-and-screen-ux.md §1.2/§3.1 (I34) — the ☰ button that opens
    /// `FindlyNavDrawer`. Only the Family Map root supplies this; every other screen leaves it
    /// `nil`, matching §1.2's "the Family Map — and only the root screen — renders a ☰ menu
    /// button." Mutually exclusive with the back chevron in practice (the root never has a back
    /// action), but if both were ever supplied, back wins — a back affordance is the more urgent
    /// signal to preserve.
    private let menuAction: (() -> Void)?
    private let trailingActionTitle: String?
    private let trailingAction: (() -> Void)?

    public init(
        _ title: String,
        onBack: (() -> Void)? = nil,
        menuAction: (() -> Void)? = nil,
        trailingActionTitle: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.onBack = onBack
        self.menuAction = menuAction
        self.trailingActionTitle = trailingActionTitle
        self.trailingAction = trailingAction
    }

    private var leadingAction: (() -> Void)? { onBack ?? environmentBackAction ?? menuAction }

    public var body: some View {
        HStack(spacing: 0) {
            if let onBack = onBack ?? environmentBackAction {
                Button(action: onBack) {
                    // SF Symbol, not a literal glyph: it mirrors for right-to-left layouts and
                    // scales with Dynamic Type automatically.
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(theme.colors.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
            } else if let menuAction {
                Button(action: menuAction) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(theme.colors.onSurface)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Menu")
            }

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.2)
                .foregroundColor(theme.colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Keep the title visually aligned even when there's no leading button.
                .padding(.leading, leadingAction == nil ? theme.spacing.md : 0)

            if let trailingActionTitle, let trailingAction {
                Button(trailingActionTitle, action: trailingAction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.colors.primary)
                    // Text alone is ~15pt tall — well under the 44pt minimum touch target the
                    // back button two lines above already enforces. `minHeight` grows the tap
                    // area without shifting the label's visual position; `contentShape` makes the
                    // whole padded frame hit-testable, not just the glyphs' own bounds (found in
                    // I27 review — matters outdoors, one-handed, in a hurry, per the handoff).
                    .frame(minHeight: 44)
                    .padding(.trailing, theme.spacing.md)
                    .contentShape(Rectangle())
            }
        }
        .frame(height: 52)
        .background(theme.colors.surface)
    }
}

#Preview("FindlyNavBar — light") {
    VStack(spacing: 1) {
        FindlyNavBar("Live map")
        FindlyNavBar("Family & devices", onBack: {}, trailingActionTitle: "Edit", trailingAction: {})
    }
    .background(Theme.light.colors.surface)
    .environment(\.theme, .light)
}

#Preview("FindlyNavBar — dark") {
    VStack(spacing: 1) {
        FindlyNavBar("Live map")
        FindlyNavBar("Family & devices", onBack: {}, trailingActionTitle: "Edit", trailingAction: {})
    }
    .background(Theme.dark.colors.surface)
    .environment(\.theme, .dark)
    .preferredColorScheme(.dark)
}
