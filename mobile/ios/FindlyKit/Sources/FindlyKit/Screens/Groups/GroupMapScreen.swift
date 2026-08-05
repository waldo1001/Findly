import SwiftUI

/// specs/004-ios-client.md §3.4 (001 §12.10; 005 §3) — composes ONLY design-system components +
/// the injected `MapRendering` base layer, exactly like `LiveMapScreen`. **Position-only**: roster
/// rows show display name + role + live/stale chip — no device rows, no battery, because
/// `GroupMemberLocation` simply doesn't carry those fields.
public struct GroupMapScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: GroupMapViewModel
    private let renderer: any MapRendering
    private let onExit: () -> Void

    public init(viewModel: @autoclosure @escaping () -> GroupMapViewModel, renderer: any MapRendering, onExit: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.renderer = renderer
        self.onExit = onExit
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Group map")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading map…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .expired:
            // 005 §2.3 — the group ended while this screen was open; there's nothing to retry.
            ErrorStateView(message: "This group has ended.", retryTitle: "Back to groups", onRetry: onExit)
        case .loaded(let members):
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    renderer.makeMapView(region: $viewModel.region, annotations: viewModel.annotations)
                        .aspectRatio(1.4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
                        .padding(.horizontal, theme.spacing.md)

                    if members.isEmpty {
                        EmptyStateView(title: "No one here yet", message: "Positions appear once members start sharing their location.")
                    } else {
                        ForEach(members, id: \.userId) { member in
                            FindlyListRow(title: member.displayName, subtitle: member.role.capitalized) {
                                statusChip(for: member)
                            }
                        }
                    }
                }
                .padding(.vertical, theme.spacing.md)
            }
        }
    }

    private func statusChip(for member: GroupMemberLocation) -> StatusChip {
        guard let location = member.location else {
            return StatusChip("No position", kind: .paused)
        }
        return location.isStale ? StatusChip("Stale", kind: .stale) : StatusChip("Live", kind: .online)
    }
}
