import SwiftUI

/// specs/010-app-shell-and-screen-ux.md §2.2 — the single Onboarding screen, replacing the retired
/// Home hub's `.profileless`/`.familyless` branches (I17's behaviors move here unchanged, incl. the
/// A21 blank-name guard, which lives at each of the four bootstrap view models — see
/// `CreateFamilyViewModel`/`AcceptInviteViewModel`/`CreateGroupViewModel`/`GroupJoinViewModel`).
///
/// A root: no back affordance (nothing behind it worth going back to — every family screen would
/// fail the same way), no drawer (010 §2.2's own words). `RootView` never gives this screen a
/// `navBarBackAction`/drawer wiring, so there is nothing to omit here either.
///
/// Composes ONLY design-system components, exactly like every other screen (004 §2.4) — no network
/// call of its own; the four bootstrap paths are separate routes/view models this screen only
/// navigates to.
public struct OnboardingScreen: View {
    @Environment(\.theme) private var theme
    private let variant: OnboardingVariant
    // The display name typed once here is carried (still editable) into whichever bootstrap path
    // the user picks — the exact "remembered local state" pattern the retired Home hub used
    // (`pendingOnboardingDisplayName`, threaded by `RootView`), not owned by this screen's own
    // navigation callbacks.
    @State private var displayName: String
    private let onSelectCreateFamily: (String) -> Void
    private let onSelectAcceptInvite: (String) -> Void
    private let onSelectCreateGroup: (String) -> Void
    private let onSelectJoinGroup: (String) -> Void
    private let onSelectGroups: () -> Void
    private let onSelectPrivacySettings: () -> Void

    public init(
        variant: OnboardingVariant,
        prefillDisplayName: String = "",
        onSelectCreateFamily: @escaping (String) -> Void,
        onSelectAcceptInvite: @escaping (String) -> Void,
        onSelectCreateGroup: @escaping (String) -> Void = { _ in },
        onSelectJoinGroup: @escaping (String) -> Void = { _ in },
        onSelectGroups: @escaping () -> Void = {},
        onSelectPrivacySettings: @escaping () -> Void
    ) {
        self.variant = variant
        self._displayName = State(initialValue: prefillDisplayName)
        self.onSelectCreateFamily = onSelectCreateFamily
        self.onSelectAcceptInvite = onSelectAcceptInvite
        self.onSelectCreateGroup = onSelectCreateGroup
        self.onSelectJoinGroup = onSelectJoinGroup
        self.onSelectGroups = onSelectGroups
        self.onSelectPrivacySettings = onSelectPrivacySettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            FindlyNavBar("Findly")
            content
        }
        .background(theme.colors.surfaceVariant)
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .profileLess:
            profileLessContent
        case .familyLess:
            familyLessContent
        }
    }

    /// 001 §1.5.3 — no `Users` profile row exists at all, so only the four bootstrap paths make
    /// sense; `GET /groups` would 404 too (§12.2 requires a profile), so Groups is deliberately
    /// NOT offered here.
    private var profileLessContent: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                EmptyStateView(
                    title: "Welcome to Findly",
                    message: "Create or join a family, or start a temporary group — pick how you'd like to get started."
                )
                FindlyTextField("Your display name", text: $displayName, placeholder: "Eric")
                FindlyButton("Create a family") { onSelectCreateFamily(displayName) }
                FindlyButton("I have an invite code", style: .secondary) { onSelectAcceptInvite(displayName) }
                FindlyButton("Create a group", style: .secondary) { onSelectCreateGroup(displayName) }
                FindlyButton("Join a group", style: .secondary) { onSelectJoinGroup(displayName) }
                // 001 §13.2 / 008 §4.1 permits DELETE /users/me even with no profile — a brand-new
                // user who decides not to proceed with onboarding still needs a way out.
                FindlyButton("Privacy & data", style: .secondary) { onSelectPrivacySettings() }
            }
            .padding(theme.spacing.xl)
        }
    }

    /// 001 §1.5.4 — a profile exists (`familyId: null`); Groups (their one live feature) is
    /// unconditionally reachable, and no display-name field is needed (they already have one).
    private var familyLessContent: some View {
        ScrollView {
            VStack(spacing: theme.spacing.md) {
                EmptyStateView(
                    title: "No family yet",
                    message: "Create or join a family, or keep using your temporary group."
                )
                FindlyButton("Create a family") { onSelectCreateFamily(displayName) }
                FindlyButton("I have an invite code", style: .secondary) { onSelectAcceptInvite(displayName) }
                FindlyButton("Groups", style: .secondary) { onSelectGroups() }
                FindlyButton("Privacy & data", style: .secondary) { onSelectPrivacySettings() }
            }
            .padding(theme.spacing.xl)
        }
    }
}
