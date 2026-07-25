import SwiftUI

/// specs/004-ios-client.md I2 — the post-sign-in navigation hub, composed ONLY from design-system
/// components. Navigation itself is the caller's responsibility (closures), matching the
/// `AppCoordinator` seam already established by I1's `SignInScreen`.
public struct HomeScreen: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var viewModel: HomeViewModel
    private let onSelectMap: () -> Void
    private let onSelectHistory: (String) -> Void
    private let onSelectGeofences: () -> Void
    private let onSelectLocate: (LocateTarget, String) -> Void
    private let onSelectDevices: (Bool) -> Void
    private let onSelectFamily: () -> Void
    private let onSelectInvite: () -> Void
    private let onSelectGroups: () -> Void
    private let onSelectPrivacySettings: () -> Void

    public init(
        viewModel: HomeViewModel,
        onSelectMap: @escaping () -> Void,
        onSelectHistory: @escaping (String) -> Void,
        onSelectGeofences: @escaping () -> Void,
        onSelectLocate: @escaping (LocateTarget, String) -> Void,
        onSelectDevices: @escaping (Bool) -> Void,
        onSelectFamily: @escaping () -> Void,
        onSelectInvite: @escaping () -> Void,
        onSelectGroups: @escaping () -> Void,
        onSelectPrivacySettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectMap = onSelectMap
        self.onSelectHistory = onSelectHistory
        self.onSelectGeofences = onSelectGeofences
        self.onSelectLocate = onSelectLocate
        self.onSelectDevices = onSelectDevices
        self.onSelectFamily = onSelectFamily
        self.onSelectInvite = onSelectInvite
        self.onSelectGroups = onSelectGroups
        self.onSelectPrivacySettings = onSelectPrivacySettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Findly")
            content
        }
        .background(theme.colors.surfaceVariant)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView(message: "Loading your family…")
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load() }
            }
        case .familyless:
            familylessContent
        case .loaded(let myUserId, let isParent, let familyName, let otherMembers):
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    Text(familyName)
                        .font(theme.typography.titleLarge)
                        .foregroundColor(theme.colors.onSurface)
                    FindlyButton("Family map") { onSelectMap() }
                    FindlyButton("My history", style: .secondary) { onSelectHistory(myUserId) }
                    FindlyButton("Geofences", style: .secondary) { onSelectGeofences() }
                    if let first = otherMembers.first {
                        FindlyButton("Locate \(first.displayName)", style: .secondary) {
                            onSelectLocate(.user(first.userId), first.displayName)
                        }
                    }
                    FindlyButton("Devices", style: .secondary) { onSelectDevices(isParent) }
                    FindlyButton("Family members", style: .secondary) { onSelectFamily() }
                    if isParent {
                        FindlyButton("Invite someone", style: .secondary) { onSelectInvite() }
                    }
                    // specs/004-ios-client.md §3.4 (005) — groups are independent of family
                    // membership; this is the minimal reachability wiring for the feature, same
                    // shape as every other button above (no bottom-nav/drawer component exists
                    // yet, per I2's own documented convention).
                    FindlyButton("Groups", style: .secondary) { onSelectGroups() }
                    // specs/008-privacy-endpoints.md §4.4 — export/delete-account MUST be
                    // reachable without contacting support (a store requirement); this is the one
                    // unconditional entry point into the privacy settings hub for a family member.
                    FindlyButton("Privacy & data", style: .secondary) { onSelectPrivacySettings() }
                }
                .padding(theme.spacing.xl)
            }
        }
    }

    /// review-gate finding #3 (specs/005 §1, 001 §1.5) — a signed-in user without a family is NOT
    /// a dead end: this is no longer a plain error banner, and Groups (the one destination that
    /// works without a family, 001 §1.5.4) is unconditionally reachable from here.
    private var familylessContent: some View {
        VStack(spacing: theme.spacing.md) {
            EmptyStateView(
                title: "No family yet",
                message: "You don't belong to a family, but you can still create or join a temporary group."
            )
            FindlyButton("Groups") { onSelectGroups() }
            // specs/008-privacy-endpoints.md §4.4 — a family-less user is still a full account
            // holder and must still be able to export/delete without contacting support.
            FindlyButton("Privacy & data", style: .secondary) { onSelectPrivacySettings() }
        }
        .padding(theme.spacing.xl)
    }
}
