import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    /// specs/010-app-shell-and-screen-ux.md §5.1 item 1 — the "Copy code" button's transient
    /// "Copied" confirmation. View-local UI state, not view-model state (mirrors how other screens
    /// keep purely-presentational transience, e.g. focus, out of the view model).
    @State private var didCopyCode = false
    /// specs/007-public-join-links.md §1, specs/004-ios-client.md §3.5 — the deployment constant
    /// the share text/QR are built against (`AppConfig.joinLinkHost`), same pattern as
    /// `GroupDetailScreen`.
    private let joinLinkHost: String

    public init(
        viewModel: @autoclosure @escaping () -> CreateInviteViewModel,
        joinLinkHost: String = AppConfig.defaultJoinLinkHost
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.joinLinkHost = joinLinkHost
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

    /// specs/010-app-shell-and-screen-ux.md §5.1 — top to bottom: the large copyable code, the
    /// real `expiresAt`-derived expiry caption (never hardcoded 72h), an on-device QR of the 007
    /// §1 family-invite link, a `Share invite` button with the 007 §4 template text, the handoff's
    /// footnote verbatim, and a `Create another` reset.
    private func createdView(code: String, role: String, expiresAt: String) -> some View {
        let shareText = CreateInviteViewModel.shareText(for: code, joinLinkHost: joinLinkHost)
        let joinLink = CreateInviteViewModel.joinLink(for: code, joinLinkHost: joinLinkHost)

        return ScrollView {
            VStack(spacing: theme.spacing.md) {
                FindlyCard {
                    VStack(spacing: theme.spacing.sm) {
                        StatusChip(role == "parent" ? "Parent invite" : "Member invite", kind: .online)
                        // §5.1 item 1: "titleLarge-class size, tabular figures, letter-spaced, in
                        // hyphenated display form" — styling lives in the InviteCodeDisplay
                        // design-system component, not here.
                        InviteCodeDisplay(CreateInviteViewModel.displayForm(for: code))
                        FindlyButton(didCopyCode ? "Copied" : "Copy code", style: .secondary) {
                            copyCodeToClipboard(CreateInviteViewModel.displayForm(for: code))
                        }
                        expiryCaption(expiresAt: expiresAt)
                    }
                }
                GroupJoinQRCodeView(text: joinLink.absoluteString)
                ShareLink("Share invite", item: shareText)
                // §5.1 item 5 — the handoff's footnote, verbatim.
                Text("Anyone with this code can see your family's locations, so send it directly to the person joining.")
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                // §5.1 item 6 — "Create another" resets the form without leaving the screen.
                FindlyButton("Create another", style: .secondary) {
                    self.role = "member"
                    emailHint = ""
                    didCopyCode = false
                    viewModel.reset()
                }
            }
            .padding(.horizontal, theme.spacing.xl)
        }
    }

    /// specs/010-app-shell-and-screen-ux.md §5.1 item 2: the fixed 72h contract sentence (001 §3.3
    /// — invites always expire in 72h, so this text is never "hardcoded" in the sense of being
    /// wrong, only the exact copy the spec mandates) PLUS the real `expiresAt`-derived local
    /// date/time — never a hardcoded 72h computed client-side. Omits the second line if the
    /// server ever sends something unparsable, rather than rendering garbage.
    @ViewBuilder
    private func expiryCaption(expiresAt: String) -> some View {
        VStack(spacing: 2) {
            Text("It works once and expires in 72 hours.")
                .font(theme.typography.bodyMedium.font)
                .foregroundColor(theme.onSurfaceMuted)
            if let localDateTime = CreateInviteViewModel.expiryLocalDateTime(for: expiresAt) {
                Text("Expires \(localDateTime)")
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.onSurfaceMuted)
            }
        }
        .multilineTextAlignment(.center)
    }

    /// specs/010-app-shell-and-screen-ux.md §5.1 item 1 — "a Copy code button that copies the bare
    /// code (display form) to the clipboard and confirms ('Copied')". `UIPasteboard` is UIKit-only
    /// (unavailable on the macOS target this package also builds for, per `Package.swift`'s
    /// platform list) — guarded so the package still builds clean on a plain macOS/CLT host.
    private func copyCodeToClipboard(_ displayForm: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = displayForm
        #endif
        didCopyCode = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopyCode = false
        }
    }
}
