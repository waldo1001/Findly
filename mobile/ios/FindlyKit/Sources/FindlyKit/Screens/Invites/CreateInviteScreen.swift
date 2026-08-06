import SwiftUI

/// specs/004-ios-client.md I2 (001 §3.3) — composes ONLY design-system components; `ShareLink` is
/// the system OS share-sheet affordance (its own chrome, not app-styled) used to hand off the
/// invite code out-of-band, exactly as specs/001 §3.3 requires.
public struct CreateInviteScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one this screen's state (e.g. `.created`) lives
    // on.
    @StateObject private var viewModel: CreateInviteViewModel
    @State private var role: String = "member"
    @State private var emailHint: String = ""

    public init(viewModel: @autoclosure @escaping () -> CreateInviteViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Invite a family member")
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
        case .creating:
            LoadingStateView(message: "Creating invite…")
        case .created(let code, let inviteRole, let expiresAt):
            createdView(code: code, role: inviteRole, expiresAt: expiresAt)
        }
    }

    private var form: some View {
        VStack(spacing: theme.spacing.md) {
            if case .error(let message) = viewModel.state {
                ErrorStateView(message: message)
            }
            HStack(spacing: theme.spacing.sm) {
                FindlyButton("Member", style: role == "member" ? .primary : .secondary) { role = "member" }
                FindlyButton("Parent", style: role == "parent" ? .primary : .secondary) { role = "parent" }
            }
            FindlyTextField("Email hint (optional)", text: $emailHint, placeholder: "name@example.com")
            FindlyButton("Create invite") {
                Task { await viewModel.createInvite(role: role, emailHint: emailHint.isEmpty ? nil : emailHint) }
            }
        }
        .padding(.horizontal, theme.spacing.xl)
    }

    private func createdView(code: String, role: String, expiresAt: String) -> some View {
        VStack(spacing: theme.spacing.md) {
            FindlyCard {
                VStack(spacing: theme.spacing.sm) {
                    Text(CreateInviteViewModel.shareText(for: code))
                        .font(theme.typography.titleMedium.font)
                        .foregroundColor(theme.colors.onSurface)
                        .multilineTextAlignment(.center)
                    StatusChip(role == "parent" ? "Parent invite" : "Member invite", kind: .online)
                }
            }
            ShareLink(item: CreateInviteViewModel.shareText(for: code))
        }
        .padding(.horizontal, theme.spacing.xl)
    }
}
