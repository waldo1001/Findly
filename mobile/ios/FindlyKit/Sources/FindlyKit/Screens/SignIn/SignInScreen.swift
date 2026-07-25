import SwiftUI

/// specs/006-phone-auth.md §4.1, specs/004-ios-client.md §4.1 — the two-step (phone entry / code
/// entry) phone sign-in screen. Composes ONLY design-system components (`FindlyNavBar`,
/// `FindlyTextField`, `FindlyButton`, `LoadingStateView`, `EmptyStateView`) and reads state from
/// `SignInViewModel`; contains no styling of its own beyond generic layout. The raw text fields
/// (`phoneInput`/`codeInput`) are local screen state — the view model's state is the enum, never a
/// bound string.
public struct SignInScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: SignInViewModel
    @State private var phoneInput: String = "+32"
    @State private var codeInput: String = ""

    public init(viewModel: SignInViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Findly")
            Spacer()
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .enteringPhone(let error):
            phoneEntry(error: error)
        case .sendingCode:
            LoadingStateView(message: "Sending code…")
        case .enteringCode(let phone, let resendSecondsLeft, let error):
            codeEntry(phone: phone, resendSecondsLeft: resendSecondsLeft, error: error)
        case .confirmingCode:
            LoadingStateView(message: "Verifying…")
        case .signedIn:
            EmptyStateView(title: "Signed in", message: "Welcome to Findly.")
        }
    }

    @ViewBuilder
    private func phoneEntry(error: String?) -> some View {
        VStack(spacing: theme.spacing.md) {
            FindlyTextField("Phone number", text: $phoneInput, placeholder: "+32…")
            if let error {
                Text(error)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.danger)
            }
            FindlyButton("Send code") {
                Task { await viewModel.submitPhoneNumber(phoneInput) }
            }
        }
        .padding(.horizontal, theme.spacing.xl)
    }

    @ViewBuilder
    private func codeEntry(phone: String, resendSecondsLeft: Int, error: String?) -> some View {
        VStack(spacing: theme.spacing.md) {
            Text("Code sent to \(phone)")
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.onSurface.opacity(0.7))
            FindlyTextField("Verification code", text: $codeInput, placeholder: "6-digit code")
            if let error {
                Text(error)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.danger)
            }
            FindlyButton("Verify") {
                Task { await viewModel.submitCode(codeInput) }
            }
            if resendSecondsLeft > 0 {
                Text("Resend in \(resendSecondsLeft)s")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurface.opacity(0.5))
            } else {
                FindlyButton("Resend code", style: .secondary) {
                    Task { await viewModel.resend() }
                }
            }
            FindlyButton("Change number", style: .secondary) {
                viewModel.changeNumber()
            }
        }
        .padding(.horizontal, theme.spacing.xl)
    }
}
