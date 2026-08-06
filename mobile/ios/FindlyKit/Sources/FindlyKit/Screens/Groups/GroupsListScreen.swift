import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §12.2) — composes ONLY design-system components. Doubles as
/// the family-less home: its empty state is never a dead end — Create/Join are always offered,
/// whether the list is empty or not.
public struct GroupsListScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: GroupsListViewModel
    private let onSelectGroup: (String) -> Void
    private let onCreateGroup: () -> Void
    private let onJoinGroup: () -> Void

    public init(
        viewModel: @autoclosure @escaping () -> GroupsListViewModel,
        onSelectGroup: @escaping (String) -> Void,
        onCreateGroup: @escaping () -> Void,
        onJoinGroup: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onSelectGroup = onSelectGroup
        self.onCreateGroup = onCreateGroup
        self.onJoinGroup = onJoinGroup
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Groups")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading groups…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let groups):
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    actionButtons
                    if groups.isEmpty {
                        EmptyStateView(
                            title: "No groups yet",
                            message: "Create a temporary group to share your location with a crowd, or join one with a code."
                        )
                    } else {
                        ForEach(groups, id: \.groupId) { group in
                            Button {
                                onSelectGroup(group.groupId)
                            } label: {
                                groupRow(group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(theme.spacing.md)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: theme.spacing.sm) {
            FindlyButton("Create a group") { onCreateGroup() }
            FindlyButton("Join a group", style: .secondary) { onJoinGroup() }
        }
    }

    private func groupRow(_ group: GroupSummary) -> some View {
        FindlyCard {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                HStack {
                    Text(group.name)
                        .font(theme.typography.titleMedium.font)
                        .foregroundColor(theme.colors.onSurface)
                    Spacer()
                    StatusChip(GroupStateChip.label(for: group.state), kind: GroupStateChip.kind(for: group.state))
                }
                Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                    .font(theme.typography.bodyMedium.font)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
                Text(GroupCountdown.text(from: group.endsAt))
                    .font(theme.typography.labelSmall.font)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
            }
        }
    }
}
