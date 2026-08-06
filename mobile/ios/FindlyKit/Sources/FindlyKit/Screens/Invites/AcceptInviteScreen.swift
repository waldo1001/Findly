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
    private let onAccepted: () -> Void

    /// [prefillDisplayName] seeds the display-name field when this screen is reached from the
    /// profile-less first-run flow (`HomeScreen`'s `.profileless` branch, I17) — same "enter it
    /// once" intent as [prefillInviteCode]'s existing deep-link prefill.
    ///
    /// [onAccepted] fires once (`.onChange(of: didJoin)` below) the instant `viewModel.state`
    /// reaches `.joined` — I24 (specs/001 §1.5.3, §4.1): `POST /invites/accept` is one of the four
    /// profile-bootstrap endpoints, so a profile-less caller's device registration (attempted at
    /// sign-in, before this screen ever ran) is guaranteed to have failed with
    /// `DeviceRegistrationError.profileNotYetBootstrapped` — this is the seam `RootView` uses to
    /// retry it now that a profile exists, rather than waiting for the next cold start. Defaults
    /// to a no-op so this screen's existing navigation-free "stay on the Welcome message" behavior
    /// is unchanged for any caller that doesn't need the side effect.
    public init(
        viewModel: @autoclosure @escaping () -> AcceptInviteViewModel,
        prefillInviteCode: String = "",
        prefillDisplayName: String = "",
        onAccepted: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self._inviteCode = State(initialValue: prefillInviteCode)
        self._displayName = State(initialValue: prefillDisplayName)
        self.onAccepted = onAccepted
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Join a family")
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
        .onChange(of: didJoin) { joined in
            if joined { onAccepted() }
        }
    }

    private var didJoin: Bool {
        if case .joined = viewModel.state { return true }
        return false
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
