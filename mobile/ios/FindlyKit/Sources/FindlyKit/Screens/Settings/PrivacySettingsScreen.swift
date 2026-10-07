import SwiftUI

/// specs/004-ios-client.md §3.6, specs/003-android-client.md §12.4 — the privacy settings hub,
/// composed ONLY from design-system components. Export and Delete-account are unconditionally
/// reachable (export: any user with a profile, 008 §3; delete-account: every authenticated user —
/// MUST be reachable without contacting support, a store requirement, 008 §4.4). Delete family is
/// shown only for a parent (008 §5.1) — the server still enforces the role check either way.
public struct PrivacySettingsScreen: View {
    @Environment(\.theme) private var theme
    // `@StateObject`, NOT `@ObservedObject` — see `HomeScreen`'s doc for the full failure mode
    // (I16). `RootView` constructs this screen's view model inline and re-evaluates on every
    // in-app navigation; `@StateObject` + `@autoclosure` keeps the first instance for this view's
    // lifetime instead of silently discarding the one `.task` observes.
    @StateObject private var viewModel: PrivacySettingsViewModel
    // specs/010 §1.4 (I64) — the one long-lived controller, handed in from the app target.
    @ObservedObject private var appLock: AppLockController
    private let onSelectExport: () -> Void
    private let onSelectDeleteAccount: () -> Void
    private let onSelectDeleteFamily: () -> Void

    public init(
        viewModel: @autoclosure @escaping () -> PrivacySettingsViewModel,
        appLock: AppLockController,
        onSelectExport: @escaping () -> Void,
        onSelectDeleteAccount: @escaping () -> Void,
        onSelectDeleteFamily: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.appLock = appLock
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

    /// specs/010 §1.4 — the app-lock toggle, off by default. Switching on runs one authentication
    /// (`setEnabled`), and a failed/cancelled one leaves it off (the binding snaps back because
    /// `setEnabled` republishes); switching off needs none. Disabled with a caption when the device
    /// has no screen lock.
    private var appLockRow: some View {
        let state = appLock.toggleState
        return FindlyToggleRow(
            title: state.label,
            subtitle: state.caption,
            isOn: Binding(
                get: { appLock.isEnabled },
                set: { newValue in Task { _ = await appLock.setEnabled(newValue) } }
            )
        )
        .disabled(!state.isInteractive)
        .clipShape(RoundedRectangle(cornerRadius: theme.corner.lg))
    }

    /// specs/008-privacy-endpoints.md §4.4 (review finding #3) — Export and Delete-account are
    /// driven by `viewModel.visibleEntries`, which is unconditional for those two regardless of
    /// `state` (a `GET /families/me` failure MUST NOT hide account deletion). Only the
    /// family-fetch error message is state-dependent, shown as a non-blocking note rather than
    /// replacing the whole screen the way the old `.loading`/`.error`/`.loaded` switch did.
    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                if case .error(let message) = viewModel.state {
                    ErrorStateView(message: message) {
                        Task { await viewModel.load() }
                    }
                }
                appLockRow
                let entries = viewModel.visibleEntries
                if entries.contains(.export) {
                    FindlyListRow(title: "Export my data", subtitle: "Download everything Findly holds about you") {
                        FindlyButton("Export", style: .secondary) { onSelectExport() }
                    }
                }
                if entries.contains(.deleteAccount) {
                    FindlyListRow(title: "Delete account", subtitle: "Permanently erase your account and its data") {
                        FindlyButton("Delete", style: .secondary) { onSelectDeleteAccount() }
                    }
                }
                if entries.contains(.deleteFamily) {
                    FindlyListRow(title: "Delete family", subtitle: "Permanently erase the whole family for everyone") {
                        FindlyButton("Delete", style: .secondary) { onSelectDeleteFamily() }
                    }
                }
            }
            .padding(theme.spacing.md)
        }
    }
}
