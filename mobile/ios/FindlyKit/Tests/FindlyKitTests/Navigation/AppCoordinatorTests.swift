import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4/§3.5 — `AppCoordinator.handleDeepLink(_:)` is the app target's
/// `onOpenURL` forwarding target for both the `findly://group-join?code=…` deep link and, since
/// specs/007, the `https://{joinLinkHost}/g#CODE` universal link (parsed in FindlyKit — the pure
/// `GroupCodeParsing` — per §3.4/§3.5). Every other `AppCoordinator` method is a trivial one-line
/// route assignment (untested elsewhere in this codebase, same as I1/I2's convention of not testing
/// pure plumbing) — `handleDeepLink` is the one case with actual conditional logic worth covering.
@MainActor
struct AppCoordinatorTests {

    @Test func handleDeepLink_validGroupJoinLink_routesToGroupJoinWithNormalizedCode() {
        let coordinator = AppCoordinator(route: .home)

        coordinator.handleDeepLink(URL(string: "findly://group-join?code=7f3k-9qrz")!)

        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))
    }

    @Test func handleDeepLink_invalidLink_leavesRouteUnchanged() {
        let coordinator = AppCoordinator(route: .home)

        coordinator.handleDeepLink(URL(string: "https://evil.example/not-a-group")!)

        #expect(coordinator.route == .home)
    }

    @Test func handleDeepLink_inviteDeepLink_isIgnoredNotMisroutedToGroupJoin() {
        let coordinator = AppCoordinator(route: .home)

        coordinator.handleDeepLink(URL(string: "findly://invite/7F3K9QRZ")!)

        #expect(coordinator.route == .home)
    }

    // MARK: - I6 https join links (specs/007, specs/004 §3.5)

    @Test func handleDeepLink_validHttpsJoinLink_routesToGroupJoinWithNormalizedCode() {
        let coordinator = AppCoordinator(route: .home, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#7f3k-9qrz")!)

        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))
    }

    @Test func handleDeepLink_httpsJoinLinkWrongHost_leavesRouteUnchanged() {
        // Never mis-routed (007 §4): a look-alike host must not be treated as the configured one.
        let coordinator = AppCoordinator(route: .home, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://evil.example/g#7F3K9QRZ")!)

        #expect(coordinator.route == .home)
    }

    @Test func handleDeepLink_httpsJoinLinkWrongPath_leavesRouteUnchanged() {
        let coordinator = AppCoordinator(route: .home, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/other#7F3K9QRZ")!)

        #expect(coordinator.route == .home)
    }

    @Test func handleDeepLink_httpsJoinLinkNoUsableFragment_routesToGroupJoinWithEmptyPrefill() {
        // 007 §4 / 003 §12.3 verbatim: "a valid link with no usable fragment opens the join screen
        // with an empty code field" — this is the ONE case where a recognized link routes with no
        // code and no error, unlike an unrecognized link (which never routes at all).
        let coordinator = AppCoordinator(route: .home, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g")!)

        #expect(coordinator.route == .groupJoin(prefillCode: ""))
    }

    @Test func handleDeepLink_httpsJoinLinkGarbageFragment_routesToGroupJoinWithEmptyPrefill() {
        let coordinator = AppCoordinator(route: .home, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#garbage!!")!)

        #expect(coordinator.route == .groupJoin(prefillCode: ""))
    }

    // MARK: - Back stack (specs/004 §2.5)
    //
    // The regression these cover: `route` used to be a single value with no history, so on a
    // platform with no hardware back button every `showX()` was a one-way door.

    @Test func atRoot_cannotGoBack() {
        let coordinator = AppCoordinator(route: .home)

        #expect(coordinator.canGoBack == false)
    }

    @Test func push_thenPop_returnsToPreviousRoute() {
        let coordinator = AppCoordinator(route: .home)

        coordinator.showGeofences()
        #expect(coordinator.route == .geofences)
        #expect(coordinator.canGoBack)

        coordinator.pop()

        #expect(coordinator.route == .home)
        #expect(coordinator.canGoBack == false)
    }

    @Test func pop_atRoot_isNoOp() {
        // The stack must never empty — there is always a screen to render.
        let coordinator = AppCoordinator(route: .home)

        coordinator.pop()

        #expect(coordinator.route == .home)
        #expect(coordinator.canGoBack == false)
    }

    @Test func multiLevelPush_popsBackOneLevelAtATime() {
        let coordinator = AppCoordinator(route: .home)

        coordinator.showGroupsList()
        coordinator.showGroupDetail(groupId: "grp_1")
        coordinator.showGroupMap(groupId: "grp_1")

        coordinator.pop()
        #expect(coordinator.route == .groupDetail(groupId: "grp_1"))

        coordinator.pop()
        #expect(coordinator.route == .groupsList)

        coordinator.pop()
        #expect(coordinator.route == .home)
        #expect(coordinator.canGoBack == false)
    }

    @Test func pushingTheRouteAlreadyOnTop_isIdempotent() {
        // A double tap must not stack a duplicate that needs two backs to escape.
        let coordinator = AppCoordinator(route: .home)

        coordinator.showGeofences()
        coordinator.showGeofences()

        coordinator.pop()

        #expect(coordinator.route == .home)
    }

    @Test func showHome_resetsTheStackToRoot() {
        // Home is the top of the app: you can never go "back" past it into a deeper screen.
        let coordinator = AppCoordinator(route: .home)

        coordinator.showGroupsList()
        coordinator.showGroupDetail(groupId: "grp_1")
        coordinator.showHome()

        #expect(coordinator.route == .home)
        #expect(coordinator.canGoBack == false)
    }

    @Test func showSignIn_resetsTheStackToRoot() {
        // specs/008 §4.4: after sign-out / account deletion no authenticated screen may remain
        // reachable behind the sign-in screen.
        let coordinator = AppCoordinator(route: .home)

        coordinator.showPrivacySettings()
        coordinator.showDeleteAccount()
        coordinator.showSignIn()

        #expect(coordinator.route == .signIn)
        #expect(coordinator.canGoBack == false)
    }

    @Test func handleDeepLink_whileRunning_pushesSoBackReturnsWhereTheUserWas() {
        let coordinator = AppCoordinator(route: .home, joinLinkHost: "join.example.test")

        coordinator.showLiveMap()
        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#7f3k-9qrz")!)
        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))

        coordinator.pop()

        #expect(coordinator.route == .liveMap)
    }

    @Test func handleDeepLink_ignoredLink_doesNotGrowTheStack() {
        let coordinator = AppCoordinator(route: .home)

        coordinator.showLiveMap()
        coordinator.handleDeepLink(URL(string: "https://evil.example/not-a-group")!)

        coordinator.pop()

        #expect(coordinator.route == .home)
    }

    // MARK: - Launch route / session restore (specs/004 §2.6)

    @Test func launchRoute_withRestoredSession_startsAtHomeNotSignIn() {
        // The regression: launch was hardcoded to .signIn, forcing SMS re-verification on every
        // cold start even though Firebase had persisted the session all along.
        let coordinator = AppCoordinator(route: AppCoordinator.launchRoute(isSignedIn: true))

        #expect(coordinator.route == .home)
        #expect(coordinator.canGoBack == false)
    }

    @Test func launchRoute_withNoSession_startsAtSignIn() {
        let coordinator = AppCoordinator(route: AppCoordinator.launchRoute(isSignedIn: false))

        #expect(coordinator.route == .signIn)
    }

    // MARK: - Deferred launch resolution (specs/004 §2.6)
    //
    // Why this exists: reading `currentUserId` in `FindlyApp.init()` constructs `Auth.auth()`
    // before `UIApplication.shared` is up. Firebase's `protectedDataInitialization` fetches
    // UIApplication by reflection and, failing that, returns early leaving `tokenManager` — an
    // implicitly-unwrapped optional — nil forever, so the first APNs callback traps. Resolution
    // therefore happens after the UI exists, and the app starts on a neutral route.

    @Test func defaultStart_isLaunching_notSignIn() {
        // Must NOT be .signIn: a returning user would see a sign-in screen flash before restore.
        let coordinator = AppCoordinator()

        #expect(coordinator.route == .launching)
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_signedIn_replacesLaunchingWithHome() {
        let coordinator = AppCoordinator()

        coordinator.resolveLaunch(isSignedIn: true)

        #expect(coordinator.route == .home)
        // .launching must not remain underneath — there is nothing to go back to.
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_signedOut_replacesLaunchingWithSignIn() {
        let coordinator = AppCoordinator()

        coordinator.resolveLaunch(isSignedIn: false)

        #expect(coordinator.route == .signIn)
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_isIgnoredOnceTheUserHasNavigatedAway() {
        // `.task` can re-fire (view identity changes, scene reattachment). Re-resolving would
        // yank a user who has already navigated back to a root.
        let coordinator = AppCoordinator()
        coordinator.resolveLaunch(isSignedIn: true)
        coordinator.showGeofences()

        coordinator.resolveLaunch(isSignedIn: true)

        #expect(coordinator.route == .geofences)
    }

    @Test func deepLink_arrivingBeforeLaunchResolves_isNotLostBehindLaunching() {
        // A cold start via a join link can deliver `onOpenURL` before `.task` runs.
        let coordinator = AppCoordinator(joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#7f3k-9qrz")!)

        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))
        // Backing out of the deep-linked screen must never reveal the splash.
        coordinator.pop()
        #expect(coordinator.route != .launching)
    }
}
