import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §3.1; I17) — composes ONLY design-system components. The
/// client's only `POST /families` entry point — see `CreateFamilyViewModel`'s doc for why this
/// screen didn't exist before I17.
///
/// [prefillDisplayName] seeds the display-name field when this screen is reached from the
/// profile-less first-run flow (`HomeScreen`'s `.profileless` branch), where the user already
/// typed their name once — same "enter it once" intent as `GroupJoinScreen`/`AcceptInviteScreen`'s
/// own `prefillDisplayName`, and `GroupJoinScreen`'s `prefillCode`.
public struct CreateFamilyScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one whose `.created` state `onChange` below
    // reads from.
    @StateObject private var viewModel: CreateFamilyViewModel
    @State private var familyName: String = ""
    @State private var displayName: String
    private let onCreated: (CreateFamilyResponse) -> Void

    public init(
        viewModel: @autoclosure @escaping () -> CreateFamilyViewModel,
        prefillDisplayName: String = "",
        onCreated: @escaping (CreateFamilyResponse) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self._displayName = State(initialValue: prefillDisplayName)
        self.onCreated = onCreated
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Create a family")
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
        .onChange(of: created) { result in
            if let result { onCreated(result) }
        }
    }

    private var created: CreateFamilyResponse? {
        if case .created(let response) = viewModel.state { return response }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .error, .created:
            form
        case .creating:
            LoadingStateView(message: "Creating family…")
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                if case .error(let message) = viewModel.state {
                    ErrorStateView(message: message)
                }
                FindlyTextField("Family name", text: $familyName, placeholder: "Wauters")
                FindlyTextField("Your display name", text: $displayName, placeholder: "Eric")
                FindlyButton("Create family") {
                    Task { await viewModel.createFamily(familyName: familyName, displayName: displayName) }
                }
            }
            .padding(.horizontal, theme.spacing.xl)
        }
    }
}
