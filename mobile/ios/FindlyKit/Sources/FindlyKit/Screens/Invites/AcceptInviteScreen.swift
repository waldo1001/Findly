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
    /// to a no-op, which simply leaves this screen showing `form` after a successful join (010
    /// §5.2 retires the old terminal "Welcome!" state entirely — see `content` below) for any
    /// caller that doesn't need the reset-to-root side effect.
    public init(
        viewModel: @autoclosure @escaping () -> AcceptInviteViewModel,
        prefillInviteCode: String = "",
        prefillDisplayName: String = "",
        onAccepted: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        // specs/010-app-shell-and-screen-ux.md §5.2 — the smart field's display form, applied to
        // the deep-link prefill too, so it opens already grouped as `XXXX-XXXX` rather than a
        // raw 8-char run.
        self._inviteCode = State(initialValue: InviteCodeParsing.liveFormat(prefillInviteCode))
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
        .task {
            // specs/010-app-shell-and-screen-ux.md §5.2, security review fix (I37 round 2) — only
            // resolve when there's no Onboarding-typed name already to prefill from.
            // `loadDisplayNameFallback()` runs its OWN confirming `GET /families/me` probe rather
            // than trusting `FamilyContextCache` — this screen is reachable via a deep link
            // arriving BEFORE the launch probe ever runs (`AppCoordinator.push`'s `.launching`
            // replacement case), so the cache can be genuinely empty here even for a caller who
            // already has a family; a fresh, self-confirming probe is correct in every arrival
            // state, not just the common one.
            guard displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await viewModel.loadDisplayNameFallback()
        }
        .onChange(of: viewModel.resolvedDisplayName) { resolved in
            if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let resolved, !resolved.isEmpty {
                displayName = resolved
            }
        }
        .onChange(of: didJoin) { joined in
            if joined { onAccepted() }
        }
    }

    private var didJoin: Bool {
        if case .joined = viewModel.state { return true }
        return false
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2 — "the join button disables until both fields
    /// are non-blank" (Android's existing guard, now the rule on both platforms).
    private var canSubmit: Bool {
        !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// specs/010-app-shell-and-screen-ux.md §5.2 — success resets to the Family Map root
    /// (`RootView`'s `.acceptInvite` case calls `onAccepted` -> `coordinator.showRoot()` the
    /// instant `state` reaches `.joined`); the retired terminal "Welcome!" dead-end is replaced by
    /// simply staying on `form` for the one frame before that reset actually happens — the exact
    /// pattern `CreateFamilyScreen`/`CreateGroupScreen` already use for their own `.created`/
    /// `.joined` success states, rather than a state-specific view nobody stays on long enough to
    /// read.
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .error, .joined:
            form
        case .joining:
            LoadingStateView(message: "Joining…")
        }
    }

    private var form: some View {
        VStack(spacing: theme.spacing.md) {
            if case .error(let message) = viewModel.state {
                ErrorStateView(message: message)
            }
            // specs/010-app-shell-and-screen-ux.md §5.2 — the smart code field: auto-uppercases,
            // strips hyphens/spaces, whitelist-filters to the Crockford base32 charset, and
            // renders as `XXXX-XXXX` while typing (`InviteCodeParsing.liveFormat`, shared pure
            // logic, unit-tested).
            FindlyTextField("Invite code", text: codeBinding, placeholder: "XXXX-XXXX")
            #if os(iOS)
            InvitePasteControl { pasted in
                // specs/010-app-shell-and-screen-ux.md §5.2 — "pasting an invite LINK extracts the
                // fragment code via the same 007 parsing": `InviteCodeParsing.normalize(_:)`
                // already handles a bare code, the legacy path-form link, AND the new
                // findly://family-join / https://{host}/f#CODE forms, so whatever the clipboard
                // held, only the extracted code (never the raw pasteboard text) reaches the field.
                if let code = InviteCodeParsing.normalize(pasted) {
                    inviteCode = InviteCodeParsing.liveFormat(code)
                }
            }
            .frame(height: 32)
            #endif
            FindlyTextField("Your name", text: $displayName, placeholder: "Noor")
            FindlyButton("Join family") {
                Task { await viewModel.accept(rawInviteCode: inviteCode, displayName: displayName) }
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, theme.spacing.xl)
    }

    /// Live-formats on every keystroke (010 §5.2) — `InviteCodeParsing.normalize(_:)` still does
    /// the final hyphen-stripped/8-char normalization at submit time, unchanged.
    private var codeBinding: Binding<String> {
        Binding(
            get: { inviteCode },
            set: { inviteCode = InviteCodeParsing.liveFormat($0) }
        )
    }
}
