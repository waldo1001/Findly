import SwiftUI

/// specs/004-ios-client.md I2 (001 §3.2, §3.5–3.6) — composes ONLY design-system components. Role
/// toggle + remove actions are shown for a parent viewer on EVERY row, including their own — §3.5/
/// §3.6 only forbid self-demotion/self-removal for the *last* parent, and the server's
/// `VALIDATION_FAILED`/`lastParent` response is the actual enforcement boundary (surfaced via
/// `viewModel.lastActionError`); the UI must not pre-emptively hide a legal action.
public struct FamilyMembersScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: FamilyMembersViewModel

    public init(viewModel: @autoclosure @escaping () -> FamilyMembersViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Family")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading family…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let familyName, let me, let members):
            list(familyName: familyName, me: me, members: members)
        }
    }

    private func list(familyName: String, me: MeSummary, members: [FamilyMember]) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                Text(familyName)
                    .font(theme.typography.titleLarge)
                    .foregroundColor(theme.colors.onSurface)
                if let lastActionError = viewModel.lastActionError {
                    ErrorStateView(message: lastActionError)
                }
                ForEach(members, id: \.userId) { member in
                    let isSelf = member.userId == me.userId
                    FindlyListRow(title: member.displayName, subtitle: member.role.capitalized) {
                        if viewModel.isParent {
                            HStack(spacing: theme.spacing.sm) {
                                FindlyButton(roleActionTitle(for: member, isSelf: isSelf), style: .secondary) {
                                    Task { await viewModel.updateRole(userId: member.userId, role: member.role == "parent" ? "member" : "parent") }
                                }
                                FindlyButton(isSelf ? "Leave family" : "Remove", style: .secondary) {
                                    Task { await viewModel.remove(userId: member.userId) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }

    /// "Step down"/"Leave family" on the signed-in parent's own row read better than "Make
    /// member"/"Remove" — the server (`lastParent` `VALIDATION_FAILED`) is what actually blocks
    /// the action when it would leave the family without a parent, not this label choice.
    private func roleActionTitle(for member: FamilyMember, isSelf: Bool) -> String {
        guard member.role == "parent" else { return "Make parent" }
        return isSelf ? "Step down" : "Make member"
    }
}
