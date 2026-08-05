import SwiftUI

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §5.4 — family deletion, composed
/// ONLY from design-system components plus `.confirmationDialog`. Two genuinely separate gates
/// (008 §5.4's "recommended: require typing the family name" layered on top of the standard
/// two-step confirm, not instead of it): (1) the "Delete family" button stays `.disabled` until the
/// typed name matches exactly, (2) tapping it only opens `.confirmationDialog` — the dialog's
/// destructive button is what actually calls `viewModel.confirmDelete()`. On completion the caller
/// still has an account (008 §5.2) — `onCompleted` routes back to Home, which already renders the
/// family-less state via `FAMILY_NOT_FOUND`.
public struct DeleteFamilyScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes (and whose `.phase` this
    // screen's own `onChange` above navigates off of).
    @StateObject private var viewModel: DeleteFamilyViewModel
    @State private var typedFamilyName: String = ""
    @State private var showConfirmation = false
    private let onCompleted: () -> Void

    public init(viewModel: @autoclosure @escaping () -> DeleteFamilyViewModel, onCompleted: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onCompleted = onCompleted
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Delete family")
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
        case .ready(let familyName):
            readyView(familyName: familyName)
        case .deleting:
            LoadingStateView(message: "Deleting the family…")
        case .completed:
            // Transient — `onCompleted()` (above) navigates away on this same tick.
            LoadingStateView(message: "Done.")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        }
    }

    private func readyView(familyName: String) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                Text(DeleteFamilyViewModel.confirmationMessage(familyName: familyName))
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface)
                FindlyTextField("Type \"\(familyName)\" to confirm", text: $typedFamilyName)
                FindlyButton("Delete family", style: .secondary) {
                    showConfirmation = true
                }
                .disabled(typedFamilyName != familyName)
            }
            .padding(theme.spacing.xl)
        }
        .confirmationDialog(
            "Delete \"\(familyName)\" for everyone?", isPresented: $showConfirmation, titleVisibility: .visible
        ) {
            Button("Delete family", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteFamilyViewModel.confirmationMessage(familyName: familyName))
        }
    }
}
