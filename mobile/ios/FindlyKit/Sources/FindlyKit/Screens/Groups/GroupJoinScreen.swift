import SwiftUI

/// specs/004-ios-client.md §3.4/§3.5 (001 §12.6) — composes ONLY design-system components. Also
/// the target of the `findly://group-join?code=…` deep link AND, since specs/007, the
/// `https://{joinLinkHost}/g#CODE` universal link: `AppCoordinator.handleDeepLink(_:)` routes here
/// with `prefillCode` already normalized (empty when a valid https link carried no usable
/// fragment, 007 §4).
public struct GroupJoinScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: GroupJoinViewModel
    @State private var code: String
    @State private var displayName: String = ""
    private let onJoined: (GroupSummary) -> Void

    public init(viewModel: GroupJoinViewModel, prefillCode: String = "", onJoined: @escaping (GroupSummary) -> Void) {
        self.viewModel = viewModel
        self._code = State(initialValue: prefillCode)
        self.onJoined = onJoined
    }

    public var body: some View {
        VStack(spacing: theme.spacing.lg) {
            FindlyNavBar("Join a group")
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
        case .joining:
            LoadingStateView(message: "Joining…")
        case .joined(let group):
            joinedView(group)
        }
    }

    private var form: some View {
        VStack(spacing: theme.spacing.md) {
            if case .error(let message) = viewModel.state {
                ErrorStateView(message: message)
            }
            FindlyTextField("Group code", text: $code, placeholder: "XXXX-XXXX")
            FindlyTextField("Your name for this group", text: $displayName, placeholder: "Noor")
            FindlyButton("Join group") {
                Task { await viewModel.join(rawCode: code, displayName: displayName) }
            }
        }
        .padding(.horizontal, theme.spacing.xl)
    }

    private func joinedView(_ group: GroupSummary) -> some View {
        VStack(spacing: theme.spacing.md) {
            EmptyStateView(title: "You're in!", message: "You've joined \(group.name).")
            FindlyButton("View group") { onJoined(group) }
        }
        .padding(.horizontal, theme.spacing.xl)
    }
}
