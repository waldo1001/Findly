import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.4 "Deep links while locked go through the §1.3 pending
/// slot and replay after unlock" — `AppCoordinator.setLocked` is the seam `AppLockController`
/// drives.
@MainActor
struct AppCoordinatorLockTests {
    private let host = "join.example.test"
    private let groupLink = URL(string: "https://join.example.test/g#aaaa-2222")!

    private func make(route: AppRoute) -> AppCoordinator {
        AppCoordinator(route: route, joinLinkHost: host)
    }

    @Test func linkWhileLocked_isStored_notNavigated() {
        let coordinator = make(route: .liveMap)
        coordinator.setLocked(true)

        coordinator.handleDeepLink(groupLink)

        #expect(coordinator.route == .liveMap)
    }

    @Test func unlock_replaysTheLinkCapturedWhileLocked_once() {
        let coordinator = make(route: .liveMap)
        coordinator.setLocked(true)
        coordinator.handleDeepLink(groupLink)

        coordinator.setLocked(false)

        #expect(coordinator.route == .groupJoin(prefillCode: "AAAA2222"))
        coordinator.pop()
        coordinator.setLocked(false)
        #expect(coordinator.route == .liveMap, "the slot was cleared before the first replay")
    }

    @Test func unlock_beforeLaunchResolution_doesNotReplay_theLinkWaitsForResolution() {
        let coordinator = make(route: .launching)
        coordinator.setLocked(true)
        coordinator.handleDeepLink(groupLink)

        coordinator.setLocked(false)
        #expect(coordinator.route == .launching)

        coordinator.resolveLaunch(destination: .familyMap)
        #expect(coordinator.route == .groupJoin(prefillCode: "AAAA2222"))
    }

    @Test func lock_doesNotChangeTheStack() {
        let coordinator = make(route: .liveMap)
        coordinator.showGeofences()

        coordinator.setLocked(true)

        #expect(coordinator.stack == [.liveMap, .geofences])
    }

    @Test func lockingTwice_isIdempotent() {
        let coordinator = make(route: .liveMap)
        coordinator.setLocked(true)
        coordinator.setLocked(true)
        coordinator.handleDeepLink(groupLink)
        coordinator.setLocked(false)
        #expect(coordinator.route == .groupJoin(prefillCode: "AAAA2222"))
    }
}
