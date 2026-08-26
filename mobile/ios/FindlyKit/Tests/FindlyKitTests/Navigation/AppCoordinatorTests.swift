import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4/§3.5 — `AppCoordinator.handleDeepLink(_:)` is the app target's
/// `onOpenURL` forwarding target for both the `findly://group-join?code=…` deep link and, since
/// specs/007, the `https://{joinLinkHost}/g#CODE` universal link (parsed in FindlyKit — the pure
/// `GroupCodeParsing` — per §3.4/§3.5). Every other `AppCoordinator` method is a trivial one-line
/// route assignment (untested elsewhere in this codebase, same as I1/I2's convention of not testing
/// pure plumbing) — `handleDeepLink` is the one case with actual conditional logic worth covering.
///
/// specs/010-app-shell-and-screen-ux.md §1.1/§6 (I34) — the retired Home hub's `.home` route is
/// gone; `.liveMap` is now the app's root (every test below that used to construct
/// `AppCoordinator(route: .home)` now uses `.liveMap`), and `showHome()` is renamed `showRoot()`
/// (stack-reset semantics unchanged, 004 §2.5).
@MainActor
struct AppCoordinatorTests {

    @Test func handleDeepLink_validGroupJoinLink_routesToGroupJoinWithNormalizedCode() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.handleDeepLink(URL(string: "findly://group-join?code=7f3k-9qrz")!)

        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))
    }

    @Test func handleDeepLink_invalidLink_leavesRouteUnchanged() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.handleDeepLink(URL(string: "https://evil.example/not-a-group")!)

        #expect(coordinator.route == .liveMap)
    }

    @Test func handleDeepLink_inviteDeepLink_isIgnoredNotMisroutedToGroupJoin() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.handleDeepLink(URL(string: "findly://invite/7F3K9QRZ")!)

        #expect(coordinator.route == .liveMap)
    }

    // MARK: - I6 https join links (specs/007, specs/004 §3.5)

    @Test func handleDeepLink_validHttpsJoinLink_routesToGroupJoinWithNormalizedCode() {
        let coordinator = AppCoordinator(route: .liveMap, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#7f3k-9qrz")!)

        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))
    }

    @Test func handleDeepLink_httpsJoinLinkWrongHost_leavesRouteUnchanged() {
        // Never mis-routed (007 §4): a look-alike host must not be treated as the configured one.
        let coordinator = AppCoordinator(route: .liveMap, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://evil.example/g#7F3K9QRZ")!)

        #expect(coordinator.route == .liveMap)
    }

    @Test func handleDeepLink_httpsJoinLinkWrongPath_leavesRouteUnchanged() {
        let coordinator = AppCoordinator(route: .liveMap, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/other#7F3K9QRZ")!)

        #expect(coordinator.route == .liveMap)
    }

    @Test func handleDeepLink_httpsJoinLinkNoUsableFragment_routesToGroupJoinWithEmptyPrefill() {
        // 007 §4 / 003 §12.3 verbatim: "a valid link with no usable fragment opens the join screen
        // with an empty code field" — this is the ONE case where a recognized link routes with no
        // code and no error, unlike an unrecognized link (which never routes at all).
        let coordinator = AppCoordinator(route: .liveMap, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g")!)

        #expect(coordinator.route == .groupJoin(prefillCode: ""))
    }

    @Test func handleDeepLink_httpsJoinLinkGarbageFragment_routesToGroupJoinWithEmptyPrefill() {
        let coordinator = AppCoordinator(route: .liveMap, joinLinkHost: "join.example.test")

        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#garbage!!")!)

        #expect(coordinator.route == .groupJoin(prefillCode: ""))
    }

    // MARK: - Back stack (specs/004 §2.5)
    //
    // The regression these cover: `route` used to be a single value with no history, so on a
    // platform with no hardware back button every `showX()` was a one-way door.

    @Test func atRoot_cannotGoBack() {
        let coordinator = AppCoordinator(route: .liveMap)

        #expect(coordinator.canGoBack == false)
    }

    @Test func push_thenPop_returnsToPreviousRoute() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showGeofences()
        #expect(coordinator.route == .geofences)
        #expect(coordinator.canGoBack)

        coordinator.pop()

        #expect(coordinator.route == .liveMap)
        #expect(coordinator.canGoBack == false)
    }

    @Test func pop_atRoot_isNoOp() {
        // The stack must never empty — there is always a screen to render.
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.pop()

        #expect(coordinator.route == .liveMap)
        #expect(coordinator.canGoBack == false)
    }

    @Test func multiLevelPush_popsBackOneLevelAtATime() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showGroupsList()
        coordinator.showGroupDetail(groupId: "grp_1")
        coordinator.showGroupMap(groupId: "grp_1")

        coordinator.pop()
        #expect(coordinator.route == .groupDetail(groupId: "grp_1"))

        coordinator.pop()
        #expect(coordinator.route == .groupsList)

        coordinator.pop()
        #expect(coordinator.route == .liveMap)
        #expect(coordinator.canGoBack == false)
    }

    @Test func pushingTheRouteAlreadyOnTop_isIdempotent() {
        // A double tap must not stack a duplicate that needs two backs to escape.
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showGeofences()
        coordinator.showGeofences()

        coordinator.pop()

        #expect(coordinator.route == .liveMap)
    }

    @Test func showRoot_resetsTheStackToTheFamilyMap() {
        // The Family Map is the top of the app: you can never go "back" past it into a deeper screen.
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showGroupsList()
        coordinator.showGroupDetail(groupId: "grp_1")
        coordinator.showRoot()

        #expect(coordinator.route == .liveMap)
        #expect(coordinator.canGoBack == false)
    }

    @Test func showSignIn_resetsTheStackToRoot() {
        // specs/008 §4.4: after sign-out / account deletion no authenticated screen may remain
        // reachable behind the sign-in screen.
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showPrivacySettings()
        coordinator.showDeleteAccount()
        coordinator.showSignIn()

        #expect(coordinator.route == .signIn)
        #expect(coordinator.canGoBack == false)
    }

    @Test func handleDeepLink_whileRunning_pushesSoBackReturnsWhereTheUserWas() {
        let coordinator = AppCoordinator(route: .liveMap, joinLinkHost: "join.example.test")

        coordinator.showGeofences()
        coordinator.handleDeepLink(URL(string: "https://join.example.test/g#7f3k-9qrz")!)
        #expect(coordinator.route == .groupJoin(prefillCode: "7F3K9QRZ"))

        coordinator.pop()

        #expect(coordinator.route == .geofences)
    }

    @Test func handleDeepLink_ignoredLink_doesNotGrowTheStack() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showGeofences()
        coordinator.handleDeepLink(URL(string: "https://evil.example/not-a-group")!)

        coordinator.pop()

        #expect(coordinator.route == .liveMap)
    }

    // MARK: - specs/010 §2.2 — Onboarding root (I34)

    @Test func showOnboarding_resetsTheStackToTheProfileLessVariant() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showGeofences()
        coordinator.showOnboarding(.profileLess)

        #expect(coordinator.route == .onboarding(.profileLess))
        #expect(coordinator.canGoBack == false)
    }

    @Test func showOnboarding_resetsTheStackToTheFamilyLessVariant() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.showHistory(userId: "u1")
        coordinator.showOnboarding(.familyLess)

        #expect(coordinator.route == .onboarding(.familyLess))
        #expect(coordinator.canGoBack == false)
    }

    // MARK: - specs/010 §1.1 — popTo falls back to the Family Map root, not the retired `.home` (I34)

    @Test func popTo_unvisitedRoute_rebuildsUnderTheFamilyMapRoot() {
        let coordinator = AppCoordinator(route: .liveMap)

        coordinator.popTo(.groupsList)

        #expect(coordinator.route == .groupsList)
        coordinator.pop()
        #expect(coordinator.route == .liveMap)
    }

    // MARK: - Launch route / session restore (specs/004 §2.6, specs/010 §1.1)

    @Test func defaultStart_isLaunching_notSignIn() {
        // Must NOT be .signIn: a returning user would see a sign-in screen flash before restore.
        let coordinator = AppCoordinator()

        #expect(coordinator.route == .launching)
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_familyMapDestination_replacesLaunchingWithTheFamilyMap() {
        let coordinator = AppCoordinator()

        coordinator.resolveLaunch(destination: .familyMap)

        #expect(coordinator.route == .liveMap)
        // .launching must not remain underneath — there is nothing to go back to.
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_signInDestination_replacesLaunchingWithSignIn() {
        let coordinator = AppCoordinator()

        coordinator.resolveLaunch(destination: .signIn)

        #expect(coordinator.route == .signIn)
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_onboardingDestination_replacesLaunchingWithTheOnboardingVariant() {
        let coordinator = AppCoordinator()

        coordinator.resolveLaunch(destination: .onboarding(.profileLess))

        #expect(coordinator.route == .onboarding(.profileLess))
        #expect(coordinator.canGoBack == false)
    }

    @Test func resolveLaunch_isIgnoredOnceTheUserHasNavigatedAway() {
        // `.task` can re-fire (view identity changes, scene reattachment). Re-resolving would
        // yank a user who has already navigated back to a root.
        let coordinator = AppCoordinator()
        coordinator.resolveLaunch(destination: .familyMap)
        coordinator.showGeofences()

        coordinator.resolveLaunch(destination: .familyMap)

        #expect(coordinator.route == .geofences)
    }

    @Test func showPostSignIn_notGatedOnLaunching_alwaysAppliesTheDestination() {
        // Unlike `resolveLaunch`, an interactive sign-in is reached from `.signIn`, never
        // `.launching` — this must apply unconditionally.
        let coordinator = AppCoordinator(route: .signIn)

        coordinator.showPostSignIn(.onboarding(.familyLess))

        #expect(coordinator.route == .onboarding(.familyLess))
        #expect(coordinator.canGoBack == false)
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
