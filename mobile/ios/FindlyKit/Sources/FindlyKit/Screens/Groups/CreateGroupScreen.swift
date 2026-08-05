import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §12.1; 005 §2.1) — composes ONLY design-system components,
/// bar the system `DatePicker` for `endsAt` (documented exception, same as `HistoryScreen`'s
/// date-range pickers and the live map's first-party MapKit).
public struct CreateGroupScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one this screen's state (e.g. `.created`, which
    // `onChange(of: created)` below fires `onCreated` from) lives on.
    @StateObject private var viewModel: CreateGroupViewModel
    @State private var name: String = ""
    @State private var endsAt: Date = Date().addingTimeInterval(24 * 3600)
    @State private var expiryPolicy: GroupExpiryPolicy = .delete
    @State private var displayName: String
    private let onCreated: (GroupSummary) -> Void

    /// [prefillDisplayName] seeds the display-name field when this screen is reached from the
    /// profile-less first-run flow (`HomeScreen`'s `.profileless` branch, I17) — same "enter it
    /// once" intent as `GroupJoinScreen`/`AcceptInviteScreen`'s own `prefillDisplayName`.
    public init(
        viewModel: @autoclosure @escaping () -> CreateGroupViewModel,
        prefillDisplayName: String = "",
        onCreated: @escaping (GroupSummary) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self._displayName = State(initialValue: prefillDisplayName)
        self.onCreated = onCreated
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Create a group")
            content
            Spacer()
        }
        .background(theme.colors.surfaceVariant)
        .onChange(of: created) { group in
            if let group { onCreated(group) }
        }
    }

    private var created: GroupSummary? {
        if case .created(let group) = viewModel.state { return group }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .error, .created:
            form
        case .creating:
            LoadingStateView(message: "Creating group…")
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                if case .error(let message) = viewModel.state {
                    ErrorStateView(message: message)
                }
                FindlyTextField("Group name", text: $name, placeholder: "Festival crew")
                DatePicker("Ends", selection: $endsAt, displayedComponents: [.date, .hourAndMinute])
                    .tint(theme.colors.primary)
                policyPicker
                Text(expiryPolicy.policyCopy)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
                FindlyTextField("Your name for this group", text: $displayName, placeholder: "Eric")
                FindlyButton("Create group") {
                    Task { await viewModel.createGroup(name: name, endsAt: endsAt, expiryPolicy: expiryPolicy, displayName: displayName) }
                }
            }
            .padding(.horizontal, theme.spacing.xl)
        }
    }

    private var policyPicker: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(GroupExpiryPolicy.allCases) { policy in
                FindlyButton(policy.title, style: expiryPolicy == policy ? .primary : .secondary) {
                    expiryPolicy = policy
                }
            }
        }
    }
}
