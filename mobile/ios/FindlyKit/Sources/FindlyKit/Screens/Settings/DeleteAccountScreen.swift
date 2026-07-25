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
    @ObservedObject private var viewModel: DeleteAccountViewModel
    @State private var showConfirmation = false
    private let onCompleted: () -> Void

    public init(viewModel: DeleteAccountViewModel, onCompleted: @escaping () -> Void) {
        self.viewModel = viewModel
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
            if phase == .completed { onCompleted() }
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
        case .completed:
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
                    .font(theme.typography.bodyMedium)
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

    /// specs/008-privacy-endpoints.md §1.3 — the backend erasure already succeeded; only the
    /// client-side Firebase step needs retrying (may require a recent sign-in).
    private var firebaseFailedView: some View {
        ErrorStateView(
            message: "Your data was deleted, but we couldn't finish signing you out. Please try again — you may need to sign in again first.",
            retryTitle: "Retry"
        ) {
            Task { await viewModel.retryFirebaseDelete() }
        }
        .padding(theme.spacing.xl)
    }
}
