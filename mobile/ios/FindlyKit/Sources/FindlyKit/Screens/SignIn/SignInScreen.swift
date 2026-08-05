import SwiftUI

/// specs/006-phone-auth.md §4.1, specs/004-ios-client.md §4.1 — the two-step (phone entry / code
/// entry) phone sign-in screen. Composes ONLY design-system components (`FindlyNavBar`,
/// `FindlyTextField`, `FindlyButton`, `LoadingStateView`, `EmptyStateView`) and reads state from
/// `SignInViewModel`; contains no styling of its own beyond generic layout. The raw text fields
/// (`phoneInput`/`codeInput`) are local screen state — the view model's state is the enum, never a
/// bound string.
public struct SignInScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline (`RootView.swift:87`),
    // including an `onSignedIn` closure baked into `SignInViewModel.init`, so this is the one
    // screen in the sweep worth double-checking for a stale-closure trap: `@StateObject` only ever
    // evaluates the FIRST `viewModel()` autoclosure for a given view identity, so every capture
    // inside that first closure is frozen for this view's lifetime, including nested closures like
    // `onSignedIn`. That is only safe if everything `onSignedIn` captures (`coordinator`, the
    // app-level `onSignedIn`, `locationRuntimeContainer`) is itself referentially stable across
    // every `RootView.body` re-evaluation — checked against `RootView.swift`/`FindlyApp.swift`:
    // all three are built exactly once in `FindlyApp.init()` (`@StateObject`/`let`, per
    // `RootView`'s own "composition root" doc) and handed into every `RootView(...)` construction
    // unchanged, so the frozen closure calls the same live instances every time it fires,
    // regardless of which `RootView.body` re-evaluation happened to be the one whose autoclosure
    // actually ran. `@StateObject` is therefore correct here too — the trap this comment checks
    // for would only be real if `onSignedIn` closed over something route- or render-specific
    // (e.g. a value threaded in fresh per navigation), which it does not.
    @StateObject private var viewModel: SignInViewModel
    @State private var phoneInput: String = "+32"
    @State private var codeInput: String = ""

    public init(viewModel: @autoclosure @escaping () -> SignInViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Findly")
            Spacer()
            content
            Spacer()
            buildLabel
        }
        .background(theme.colors.surfaceVariant)
    }

    /// Version + build shown on the sign-in screen so a TestFlight tester can tell at a glance
    /// *which* build they are looking at. Added 2026-08-05 after a session where two builds were
    /// uploaded minutes apart and there was no way to confirm which one had installed — the
    /// difference between them was whether the app could reach the backend at all.
    ///
    /// Also surfaces the API host, because the bug that prompted this was the app silently
    /// shipping the `.invalid` placeholder base URL: "which backend am I actually talking to"
    /// turned out to be the single most useful thing to be able to see on-device.
    @ViewBuilder
    private var buildLabel: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let host = (info?["FindlyBaseURL"] as? String).flatMap { URL(string: $0)?.host } ?? "unconfigured"
        Text("v\(version) (\(build)) · \(host)")
            .font(theme.typography.labelSmall)
            .foregroundColor(theme.colors.outline)
            .padding(.bottom, theme.spacing.sm)
            .accessibilityIdentifier("signIn.buildLabel")
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
