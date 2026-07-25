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
}
