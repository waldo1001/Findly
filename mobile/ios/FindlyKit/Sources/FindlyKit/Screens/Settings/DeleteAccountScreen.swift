import SwiftUI

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §4 — account deletion, composed
/// ONLY from design-system components plus `.confirmationDialog` (the I5-established
/// system-primitive exception). Two-step: a first tap only reveals the confirmation dialog (no
/// network call — see `DeleteAccountViewModelTests` for the equivalent ViewModel-level gating
/// proof); the dialog's destructive button is what actually calls `viewModel.confirmDelete()`. The
/// cascade wording (008 §4.2) is baked into `DeleteAccountViewModel.confirmationMessage` so the
/// exact "only parent" copy is unit-tested, not just eyeballed here.
public struct DeleteAccountScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes (and whose `.phase` this
    // screen's own `onChange` above navigates off of).
    @StateObject private var viewModel: DeleteAccountViewModel
    @State private var showConfirmation = false
    private let onCompleted: () -> Void

    public init(viewModel: @autoclosure @escaping () -> DeleteAccountViewModel, onCompleted: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onCompleted = onCompleted
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Delete account")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
        .onChange(of: viewModel.phase) { phase in
            // specs/008-privacy-endpoints.md §1.3 (review finding #4) — `.signedOutForRetry`
            // navigates to sign-in exactly like `.completed`: local state was deliberately NOT
            // wiped (the account isn't confirmed torn down client-side yet), but there is nothing
            // left for THIS screen to do — the user signs back in and re-opens it to finish.
            if phase == .completed || phase == .signedOutForRetry { onCompleted() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            LoadingStateView(message: "Loading…")
        case .ready(let cascadeWarning):
            readyView(cascadeWarning: cascadeWarning)
        case .deleting:
            LoadingStateView(message: "Deleting your account…")
        case .firebaseDeleteFailed:
            firebaseFailedView
        case .completed, .signedOutForRetry:
            // Transient — `onCompleted()` (above) navigates away on this same tick.
            LoadingStateView(message: "Done.")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        }
    }

    private func readyView(cascadeWarning: Bool) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                Text(DeleteAccountViewModel.confirmationMessage(cascadeWarning: cascadeWarning))
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.onSurface)
                FindlyButton("Delete account", style: .secondary) {
                    showConfirmation = true
                }
            }
            .padding(theme.spacing.xl)
        }
        .confirmationDialog(
            "Delete your account?", isPresented: $showConfirmation, titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteAccountViewModel.confirmationMessage(cascadeWarning: cascadeWarning))
        }
    }

    /// specs/008-privacy-endpoints.md §1.3 (review finding #4) — the backend erasure already
    /// succeeded; the client-side Firebase step failed, commonly because it needs a recent
    /// sign-in. A bare retry is a trap (it would fail identically forever), so the only offered
    /// action is `signOutForRetry()`: sign out now, sign back in through the normal flow, then
    /// re-open this screen — the backend call is an idempotent no-op and the fresh session lets
    /// the Firebase step succeed.
    private var firebaseFailedView: some View {
        ErrorStateView(
            message: "Your data was deleted, but we couldn't finish removing your sign-in. Sign out, then sign back in and try deleting again.",
            retryTitle: "Sign out"
        ) {
            Task { await viewModel.signOutForRetry() }
        }
        .padding(theme.spacing.xl)
    }
}
