import SwiftUI

/// specs/004-ios-client.md §3.6, specs/003-android-client.md §12.4 — the privacy settings hub,
/// composed ONLY from design-system components. Export and Delete-account are unconditionally
/// reachable (export: any user with a profile, 008 §3; delete-account: every authenticated user —
/// MUST be reachable without contacting support, a store requirement, 008 §4.4). Delete family is
/// shown only for a parent (008 §5.1) — the server still enforces the role check either way.
public struct PrivacySettingsScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: PrivacySettingsViewModel
    private let onSelectExport: () -> Void
    private let onSelectDeleteAccount: () -> Void
    private let onSelectDeleteFamily: () -> Void

    public init(
        viewModel: PrivacySettingsViewModel,
        onSelectExport: @escaping () -> Void,
        onSelectDeleteAccount: @escaping () -> Void,
        onSelectDeleteFamily: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectExport = onSelectExport
        self.onSelectDeleteAccount = onSelectDeleteAccount
        self.onSelectDeleteFamily = onSelectDeleteFamily
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Privacy & data")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .loaded(let isParent):
            list(isParent: isParent)
        }
    }

    private func list(isParent: Bool) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                FindlyListRow(title: "Export my data", subtitle: "Download everything Findly holds about you") {
                    FindlyButton("Export", style: .secondary) { onSelectExport() }
                }
                FindlyListRow(title: "Delete account", subtitle: "Permanently erase your account and its data") {
                    FindlyButton("Delete", style: .secondary) { onSelectDeleteAccount() }
                }
                if isParent {
                    FindlyListRow(title: "Delete family", subtitle: "Permanently erase the whole family for everyone") {
                        FindlyButton("Delete", style: .secondary) { onSelectDeleteFamily() }
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }
}
