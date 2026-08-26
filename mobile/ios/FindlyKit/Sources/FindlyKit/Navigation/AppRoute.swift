/// specs/004-ios-client.md §1.2 — the navigation scaffold. I2 adds the feature-screen routes below
/// (map, history, geofences, locate, settings, invites) on top of I1's `signIn`/`home` seam. I5
/// (§3.4) adds the groups screens on top of that — same inventory as 003 §12.2's Android screens.
public enum AppRoute: Equatable {
    /// specs/004 §2.6 — the neutral start route: a themed splash shown only until `RootView`'s
    /// first appear resolves the real one.
    ///
    /// It exists so the app can start **without touching `FirebaseAuth`**. Reading
    /// `currentUserId` in `FindlyApp.init()` constructs `Auth.auth()` before
    /// `UIApplication.shared` is up; Firebase's `protectedDataInitialization` fetches
    /// UIApplication by reflection and, failing, returns early leaving `tokenManager` (an
    /// implicitly-unwrapped optional) nil for the life of the process — so the first APNs
    /// callback traps in `Auth.setAPNSToken`. Starting at `.signIn` instead would also flash a
    /// sign-in screen at every launch for an already-signed-in user, which §2.6 exists to prevent.
    case launching
    case signIn
    /// specs/010-app-shell-and-screen-ux.md §1.1/§6 — the app's ROOT for a signed-in, profiled,
    /// familied user (renders `LiveMapScreen`, `FindlyNavDrawer` behind its ☰ button). Retired
    /// Home hub's `.home` case is gone; this is now the reset target of `AppCoordinator.showRoot()`
    /// (the renamed `showHome()` — the reset-the-stack semantics are unchanged, 004 §2.5).
    case liveMap

    // MARK: - I34 Onboarding root (specs/010-app-shell-and-screen-ux.md §2.2; 001 §1.5.3/§1.5.4) —
    // replaces the retired `.home` hub's `profileless`/`familyless` branches. A root like `.signIn`/
    // `.liveMap`: no back affordance, no drawer (§2.2). `Equatable`'s synthesized conformance
    // distinguishes the two variants, so `AppCoordinator.popTo`/`==` work unchanged.
    case onboarding(OnboardingVariant)
    case history(userId: String, deviceId: String?)
    case geofences
    case locate(target: LocateTarget, targetDisplayName: String)
    case deviceSettings(isParent: Bool)
    case familyMembers
    case createInvite
    case acceptInvite(prefillCode: String)

    // MARK: - I17 profile-bootstrap route (001 §1.5.3, §3.1) — the client's only `POST /families`
    // destination, reachable both ordinarily and from the profile-less first-run flow (the retired
    // Home hub's `.profileless` branch; now `.onboarding(.profileLess)`, I34). No associated
    // `prefillDisplayName` value — unlike
    // `.acceptInvite`/`.groupJoin`'s `prefillCode` (untrusted deep-link input that must travel with
    // the route itself), the onboarding display name is trusted in-app text the user just typed;
    // `RootView` threads it the same "remembered local state" way Android's `FindlyNavHost` threads
    // its `pendingOnboardingDisplayName` (specs/003 §12.2/A21), keeping this enum's existing,
    // already-tested cases (`.groupJoin(prefillCode:)` etc., `AppCoordinatorTests`) untouched.
    case createFamily

    // MARK: - I5 groups routes (specs/004 §3.4; specs/005)

    case groupsList
    case createGroup
    case groupDetail(groupId: String)
    case groupJoin(prefillCode: String)
    case groupMap(groupId: String)

    // MARK: - I8 privacy routes (specs/004 §3.6; specs/008)

    case privacySettings
    case exportData
    case deleteAccount
    case deleteFamily
}
