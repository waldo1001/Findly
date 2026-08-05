import SwiftUI

/// specs/004-ios-client.md I2 (001 §3.4) — composes ONLY design-system components.
public struct AcceptInviteScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one this screen's state (e.g. `.joined`) lives
    // on.
    @StateObject private var viewModel: AcceptInviteViewModel
    @State private var inviteCode: String
    @State private var displayName: String

    /// [prefillDisplayName] seeds the display-name field when this screen is reached from the
    /// profile-less first-run flow (`HomeScreen`'s `.profileless` branch, I17) — same "enter it
    /// once" intent as [prefillInviteCode]'s existing deep-link prefill.
    public init(
        viewModel: @autoclosure @escaping () -> AcceptInviteViewModel,
        prefillInviteCode: String = "",
        prefillDisplayName: String = ""
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self._inviteCode = State(initialValue: prefillInviteCode)
        self._displayName = State(initialValue: prefillDisplayName)
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Join a family")
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .error:
            form
        case .joining:
            LoadingStateView(message: "Joining…")
        case .joined(_, let familyName, _):
            EmptyStateView(title: "Welcome!", message: "You've joined \(familyName).")
        }
    }

    private var form: some View {
        VStack(spacing: theme.spacing.md) {
            if case .error(let message) = viewModel.state {
                ErrorStateView(message: message)
            }
            FindlyTextField("Invite code", text: $inviteCode, placeholder: "XXXX-XXXX")
            FindlyTextField("Your name", text: $displayName, placeholder: "Noor")
            FindlyButton("Join family") {
                Task { await viewModel.accept(rawInviteCode: inviteCode, displayName: displayName) }
            }
        }
        .padding(.horizontal, theme.spacing.xl)
    }
}
