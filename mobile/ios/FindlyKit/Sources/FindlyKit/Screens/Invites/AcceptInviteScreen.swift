import SwiftUI

/// specs/004-ios-client.md I2 (001 §3.4) — composes ONLY design-system components.
public struct AcceptInviteScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: AcceptInviteViewModel
    @State private var inviteCode: String
    @State private var displayName: String = ""

    public init(viewModel: AcceptInviteViewModel, prefillInviteCode: String = "") {
        self.viewModel = viewModel
        self._inviteCode = State(initialValue: prefillInviteCode)
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
