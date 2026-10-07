import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.3 (H20 / 000 §D20, row I63) — `AppCoordinator`'s capture
/// and replay of join/invite links that arrive while the app cannot act on them yet.
@MainActor
struct AppCoordinatorPendingLinkTests {

    private let host = "join.example.test"
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func make(
        route: AppRoute = .launching, store: PendingLinkStoring = InMemoryPendingLinkStore()
    ) -> (AppCoordinator, Clock, PendingLinkStoring) {
        let clock = Clock(t0)
        let slot = PendingLinkSlot(store: store, now: { clock.now })
        return (AppCoordinator(route: route, joinLinkHost: host, pendingLinks: slot), clock, store)
    }

    private let familyLink = URL(string: "https://join.example.test/f#7f3k-9qrz")!
    private let groupLink = URL(string: "https://join.example.test/g#aaaa-2222")!

    // MARK: - Capture: stored, never navigated

    @Test func link_whileLaunching_isStored_notNavigated() {
        let (coordinator, _, store) = make(route: .launching)

        coordinator.handleDeepLink(familyLink)

        #expect(coordinator.route == .launching)
        #expect(store.load()?.kind == .familyInvite)
        #expect(store.load()?.code == "7F3K9QRZ")
    }

    @Test func link_whileSignedOut_isStored_notNavigated_andSignInStaysTheRoot() {
        let (coordinator, _, store) = make(route: .signIn)

        coordinator.handleDeepLink(groupLink)

        #expect(coordinator.route == .signIn)
        #expect(coordinator.canGoBack == false)
        #expect(store.load()?.kind == .groupJoin)
        #expect(store.load()?.code == "AAAA2222")
    }

    @Test func legacyFindlySchemeLinks_areCapturedToo_forBothKinds() {
        let (coordinator, _, store) = make(route: .signIn)

        coordinator.handleDeepLink(URL(string: "findly://family-join?code=7f3k-9qrz")!)
        #expect(store.load()?.kind == .familyInvite)

        coordinator.handleDeepLink(URL(string: "findly://group-join?code=aaaa-2222")!)
        #expect(store.load()?.kind == .groupJoin)
        #expect(coordinator.route == .signIn)
    }

    @Test func newerLink_replacesOlder() {
        let (coordinator, _, store) = make(route: .signIn)

        coordinator.handleDeepLink(familyLink)
        coordinator.handleDeepLink(groupLink)

        #expect(store.load()?.kind == .groupJoin)
    }

    @Test func unparseableLink_whileSignedOut_isIgnored_notStored() {
        let (coordinator, _, store) = make(route: .signIn)

        coordinator.handleDeepLink(URL(string: "https://evil.example/f#7F3K9QRZ")!)
        coordinator.handleDeepLink(URL(string: "https://join.example.test/f#garbage!!")!)
        coordinator.handleDeepLink(URL(string: "https://join.example.test/f")!)

        #expect(store.load() == nil)
        #expect(coordinator.route == .signIn)
    }

    @Test func linkWhileAppCanAct_isHandledImmediately_exactlyAsToday_andNothingIsStored() {
        let (coordinator, _, store) = make(route: .liveMap)

        coordinator.handleDeepLink(familyLink)

        #expect(coordinator.route == .acceptInvite(prefillCode: "7F3K9QRZ"))
        #expect(store.load() == nil)
    }

    @Test func linkWhileLocked_isStored_notNavigated() {
        let (coordinator, _, store) = make(route: .liveMap)
        coordinator.isLocked = true

        coordinator.handleDeepLink(familyLink)

        #expect(coordinator.route == .liveMap)
        #expect(store.load() != nil)
    }

    // MARK: - Replay after launch resolution

    @Test func coldStart_resolvesToFamilyMap_replaysFamilyInviteAboveTheRoot_prefilled() {
        let (coordinator, _, store) = make(route: .launching)
        coordinator.handleDeepLink(familyLink)

        coordinator.resolveLaunch(destination: .familyMap)

        #expect(coordinator.route == .acceptInvite(prefillCode: "7F3K9QRZ"))
        coordinator.pop()
        #expect(coordinator.route == .liveMap, "pushed ABOVE the resolved root, so back lands on it")
        #expect(store.load() == nil)
    }

    @Test func coldStart_resolvesToOnboarding_replaysGroupJoinAboveOnboarding() {
        let (coordinator, _, _) = make(route: .launching)
        coordinator.handleDeepLink(groupLink)

        coordinator.resolveLaunch(destination: .onboarding(.profileLess))

        #expect(coordinator.route == .groupJoin(prefillCode: "AAAA2222"))
        coordinator.pop()
        #expect(coordinator.route == .onboarding(.profileLess))
    }

    @Test func coldStart_resolvesToSignIn_keepsThePendingLink() {
        let (coordinator, _, store) = make(route: .launching)
        coordinator.handleDeepLink(familyLink)

        coordinator.resolveLaunch(destination: .signIn)

        #expect(coordinator.route == .signIn)
        #expect(store.load() != nil)
    }

    @Test func afterSignIn_replaysTheLinkCapturedWhileSignedOut() {
        let (coordinator, clock, store) = make(route: .signIn)
        coordinator.handleDeepLink(familyLink)
        clock.now = t0.addingTimeInterval(300) // reading the SMS code

        coordinator.showPostSignIn(.familyMap)

        #expect(coordinator.route == .acceptInvite(prefillCode: "7F3K9QRZ"))
        coordinator.pop()
        #expect(coordinator.route == .liveMap)
        #expect(store.load() == nil)
    }

    @Test func afterSignIn_toOnboarding_replaysAboveOnboarding() {
        let (coordinator, _, _) = make(route: .signIn)
        coordinator.handleDeepLink(familyLink)

        coordinator.showPostSignIn(.onboarding(.profileLess))

        #expect(coordinator.route == .acceptInvite(prefillCode: "7F3K9QRZ"))
        coordinator.pop()
        #expect(coordinator.route == .onboarding(.profileLess))
    }

    @Test func expiredLink_isDiscardedAtReplay_andNothingNavigates() {
        let (coordinator, clock, store) = make(route: .signIn)
        coordinator.handleDeepLink(familyLink)
        clock.now = t0.addingTimeInterval(3600)

        coordinator.showPostSignIn(.familyMap)

        #expect(coordinator.route == .liveMap)
        #expect(store.load() == nil)
    }

    @Test func replay_happensOnce() {
        let (coordinator, _, _) = make(route: .signIn)
        coordinator.handleDeepLink(familyLink)
        coordinator.showPostSignIn(.familyMap)
        coordinator.pop()

        coordinator.showPostSignIn(.familyMap)

        #expect(coordinator.route == .liveMap)
    }

    @Test func replayPendingLinkIfPossible_afterUnlock_replaysTheLinkCapturedWhileLocked() {
        let (coordinator, _, _) = make(route: .liveMap)
        coordinator.isLocked = true
        coordinator.handleDeepLink(groupLink)

        coordinator.isLocked = false
        coordinator.replayPendingLinkIfPossible()

        #expect(coordinator.route == .groupJoin(prefillCode: "AAAA2222"))
    }

    @Test func linkSurvivesProcessDeath_whileTheUserReadsTheSms() {
        let store = InMemoryPendingLinkStore()
        let (first, _, _) = make(route: .signIn, store: store)
        first.handleDeepLink(familyLink)

        let (relaunched, _, _) = make(route: .launching, store: store)
        relaunched.resolveLaunch(destination: .familyMap)

        #expect(relaunched.route == .acceptInvite(prefillCode: "7F3K9QRZ"))
    }
}
