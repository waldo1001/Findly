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

    // MARK: - I5 groups routes (specs/004 §3.4; specs/005)

    case groupsList
    case createGroup
    case groupDetail(groupId: String)
    case groupJoin(prefillCode: String)
    case groupMap(groupId: String)
}
