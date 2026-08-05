import SwiftUI

/// specs/004-ios-client.md I2 — the post-sign-in navigation hub, composed ONLY from design-system
/// components. Navigation itself is the caller's responsibility (closures), matching the
/// `AppCoordinator` seam already established by I1's `SignInScreen`.
public struct HomeScreen: View {
    @Environment(\.theme) private var theme
    /// `@StateObject`, NOT `@ObservedObject` (2026-08-05). `RootView` constructs this screen's
    /// view model inline in its own `body`, and `RootView` re-evaluates on every
    /// `coordinator.route` publish — i.e. on every in-app navigation. With `@ObservedObject` that
    /// produced a fresh, still-`.loading` view model on each re-evaluation while `.task` (bound to
    /// the unchanged view identity) never re-ran, so the instance that actually completed `load()`
    /// was no longer the one the view observed. Symptom: the screen sat on "Loading your family…"
    /// forever even though `load()` had finished in ~46 ms and correctly resolved to `.familyless`.
    /// `@StateObject` keeps the first instance for the view's lifetime and discards the
    /// re-constructed ones, which is what makes the `.task`/observation pair coherent.
    @StateObject private var viewModel: HomeViewModel
    // I17 (001 §1.5.3) — the display name typed once on `profilelessContent`, carried (still
    // editable) into whichever of the four bootstrap paths the user picks. Local `@State`, not
    // view-model state: this screen's own body already holds `displayName`-style form fields as
    // plain `@State` nowhere else, but the four bootstrap actions below are simple one-shot
    // navigations (mirroring `CreateGroupScreen`/`GroupJoinScreen`'s own local-field pattern), not
    // something `HomeViewModel` needs to own.
    @State private var profileDisplayName: String = ""
    private let onSelectMap: () -> Void
    private let onSelectHistory: (String) -> Void
    private let onSelectGeofences: () -> Void
    private let onSelectLocate: (LocateTarget, String) -> Void
    private let onSelectDevices: (Bool) -> Void
    private let onSelectFamily: () -> Void
    private let onSelectInvite: () -> Void
    private let onSelectGroups: () -> Void
    private let onSelectPrivacySettings: () -> Void
    // MARK: - I17 profile-bootstrap paths (001 §1.5.3) — reachable only from `.profileless`.
    private let onSelectCreateFamily: (String) -> Void
    private let onSelectAcceptInvite: (String) -> Void
    private let onSelectCreateGroup: (String) -> Void
    private let onSelectJoinGroup: (String) -> Void

    public init(
        viewModel: @autoclosure @escaping () -> HomeViewModel,
        onSelectMap: @escaping () -> Void,
        onSelectHistory: @escaping (String) -> Void,
        onSelectGeofences: @escaping () -> Void,
        onSelectLocate: @escaping (LocateTarget, String) -> Void,
        onSelectDevices: @escaping (Bool) -> Void,
        onSelectFamily: @escaping () -> Void,
        onSelectInvite: @escaping () -> Void,
        onSelectGroups: @escaping () -> Void,
        onSelectPrivacySettings: @escaping () -> Void,
        onSelectCreateFamily: @escaping (String) -> Void,
        onSelectAcceptInvite: @escaping (String) -> Void,
        onSelectCreateGroup: @escaping (String) -> Void,
        onSelectJoinGroup: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.onSelectMap = onSelectMap
        self.onSelectHistory = onSelectHistory
        self.onSelectGeofences = onSelectGeofences
        self.onSelectLocate = onSelectLocate
        self.onSelectDevices = onSelectDevices
        self.onSelectFamily = onSelectFamily
        self.onSelectInvite = onSelectInvite
        self.onSelectGroups = onSelectGroups
        self.onSelectPrivacySettings = onSelectPrivacySettings
        self.onSelectCreateFamily = onSelectCreateFamily
        self.onSelectAcceptInvite = onSelectAcceptInvite
        self.onSelectCreateGroup = onSelectCreateGroup
        self.onSelectJoinGroup = onSelectJoinGroup
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
        case .profileless:
            profilelessContent
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

    /// I17 (001 §1.5.3) — a brand-new signed-in user with no `Users` profile row at all. DISTINCT
    /// from [familylessContent]: `GET /groups` would 404 for this caller too (§12.2 requires a
    /// profile), so Groups is deliberately NOT offered here — only the four profile-bootstrapping
    /// paths are (§3.1/§3.4/§12.1/§12.6), each carrying the one display name typed below.
    private var profilelessContent: some View {
        VStack(spacing: theme.spacing.md) {
            EmptyStateView(
                title: "Welcome to Findly",
                message: "Create or join a family, or start a temporary group — pick how you'd like to get started."
            )
            FindlyTextField("Your display name", text: $profileDisplayName, placeholder: "Eric")
            FindlyButton("Create a family") { onSelectCreateFamily(profileDisplayName) }
            FindlyButton("I have an invite code", style: .secondary) { onSelectAcceptInvite(profileDisplayName) }
            FindlyButton("Create a group", style: .secondary) { onSelectCreateGroup(profileDisplayName) }
            FindlyButton("Join a group", style: .secondary) { onSelectJoinGroup(profileDisplayName) }
        }
        .padding(theme.spacing.xl)
    }
}
