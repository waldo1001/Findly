/// specs/004-ios-client.md §1.2 — the navigation scaffold. I2 adds the feature-screen routes below
/// (map, history, geofences, locate, settings, invites) on top of I1's `signIn`/`home` seam. I5
/// (§3.4) adds the groups screens on top of that — same inventory as 003 §12.2's Android screens.
public enum AppRoute: Equatable {
    case signIn
    case home
    case liveMap
    case history(userId: String, deviceId: String?)
    case geofences
    case locate(target: LocateTarget, targetDisplayName: String)
    case deviceSettings(isParent: Bool)
    case familyMembers
    case createInvite
    case acceptInvite(prefillCode: String)

    // MARK: - I17 profile-bootstrap route (001 §1.5.3, §3.1) — the client's only `POST /families`
    // destination, reachable both ordinarily and from the profile-less first-run flow
    // (`HomeScreen`'s `.profileless` branch). No associated `prefillDisplayName` value — unlike
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
