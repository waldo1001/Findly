import Foundation

/// specs/004-ios-client.md §1.2, §2.4 — owns the current route. Contains zero styling; the app
/// target's root view switches on `route` to pick which screen (composed from design-system
/// components) to show.
@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var route: AppRoute
    /// specs/004-ios-client.md §3.5, specs/007-public-join-links.md §1 — the deployment constant
    /// `handleDeepLink` matches https universal links against (`AppConfig.joinLinkHost`).
    private let joinLinkHost: String

    public init(route: AppRoute = .signIn, joinLinkHost: String = AppConfig.defaultJoinLinkHost) {
        self.route = route
        self.joinLinkHost = joinLinkHost
    }

    public func showSignIn() {
        route = .signIn
    }

    public func showHome() {
        route = .home
    }

    // MARK: - I2 feature-screen routes

    public func showLiveMap() {
        route = .liveMap
    }

    public func showHistory(userId: String, deviceId: String? = nil) {
        route = .history(userId: userId, deviceId: deviceId)
    }

    public func showGeofences() {
        route = .geofences
    }

    public func showLocate(target: LocateTarget, targetDisplayName: String) {
        route = .locate(target: target, targetDisplayName: targetDisplayName)
    }

    public func showDeviceSettings(isParent: Bool) {
        route = .deviceSettings(isParent: isParent)
    }

    public func showFamilyMembers() {
        route = .familyMembers
    }

    public func showCreateInvite() {
        route = .createInvite
    }

    public func showAcceptInvite(prefillCode: String = "") {
        route = .acceptInvite(prefillCode: prefillCode)
    }

    // MARK: - I17 profile-bootstrap route (001 §1.5.3, §3.1)

    public func showCreateFamily() {
        route = .createFamily
    }

    // MARK: - I5 groups routes (specs/004 §3.4)

    public func showGroupsList() {
        route = .groupsList
    }

    public func showCreateGroup() {
        route = .createGroup
    }

    public func showGroupDetail(groupId: String) {
        route = .groupDetail(groupId: groupId)
    }

    public func showGroupJoin(prefillCode: String = "") {
        route = .groupJoin(prefillCode: prefillCode)
    }

    public func showGroupMap(groupId: String) {
        route = .groupMap(groupId: groupId)
    }

    // MARK: - I8 privacy routes (specs/004 §3.6; specs/008)

    public func showPrivacySettings() {
        route = .privacySettings
    }

    public func showExportData() {
        route = .exportData
    }

    public func showDeleteAccount() {
        route = .deleteAccount
    }

    public func showDeleteFamily() {
        route = .deleteFamily
    }

    /// The app target's `onOpenURL` forwards here (specs/004 §3.4/§3.5) — `GroupCodeParsing` (pure,
    /// FindlyKit) validates/normalizes the incoming link BEFORE any route change. Two forms are
    /// recognized: the legacy `findly://group-join?code=…` scheme (unchanged behavior — an
    /// unrecognized/codeless link is silently ignored, no route change, no crash) and, since 007,
    /// the `https://{joinLinkHost}/g#CODE` universal link, where a recognized host+path with no
    /// usable fragment DOES route to the join screen with an empty prefill (007 §4 / 003 §12.3) —
    /// a deliberate difference from the `findly://` case, since only the https form's contract
    /// specifies that behavior. A URL matching neither form is silently ignored either way, rather
    /// than surfacing a raw error for what may be an unrelated/malformed external URL.
    public func handleDeepLink(_ url: URL) {
        if let code = GroupCodeParsing.normalize(url.absoluteString) {
            route = .groupJoin(prefillCode: code)
            return
        }
        if case .recognized(let code) = GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: joinLinkHost) {
            route = .groupJoin(prefillCode: code ?? "")
        }
    }
}
