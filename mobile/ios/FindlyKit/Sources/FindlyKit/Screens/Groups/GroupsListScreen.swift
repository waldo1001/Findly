import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §12.2) — composes ONLY design-system components. Doubles as
/// the family-less home: its empty state is never a dead end — Create/Join are always offered,
/// whether the list is empty or not.
public struct GroupsListScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: GroupsListViewModel
    private let onSelectGroup: (String) -> Void
    private let onCreateGroup: () -> Void
    private let onJoinGroup: () -> Void

    public init(
        viewModel: GroupsListViewModel,
        onSelectGroup: @escaping (String) -> Void,
        onCreateGroup: @escaping () -> Void,
        onJoinGroup: @escaping () -> Void
    ) {
        self.viewModel = viewModel
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
                        .font(theme.typography.titleMedium)
                        .foregroundColor(theme.colors.onSurface)
                    Spacer()
                    StatusChip(GroupStateChip.label(for: group.state), kind: GroupStateChip.kind(for: group.state))
                }
                Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
                Text(GroupCountdown.text(from: group.endsAt))
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurface.opacity(0.7))
            }
        }
    }
}
