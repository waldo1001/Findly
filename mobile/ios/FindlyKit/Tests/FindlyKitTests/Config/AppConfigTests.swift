import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §8, specs/006-phone-auth.md §5 — `firebaseProjectId` feeds
/// `StubAuthProvider`'s fake `iss`/`aud` in dev mode; H1 supplies the real Firebase project id via
/// the app target's build configuration, never by editing this default.
struct AppConfigTests {

    @Test func defaultAuthModeIsStubLocal() {
        #expect(AppConfig().authMode == .stubLocal)
    }

    @Test func firebaseProjectIdHasANonEmptyDevDefault() {
        #expect(!AppConfig().firebaseProjectId.isEmpty)
    }

    @Test func firebaseProjectIdIsConfigurable() {
        let config = AppConfig(firebaseProjectId: "some-other-project")
        #expect(config.firebaseProjectId == "some-other-project")
    }

    // specs/004-ios-client.md §3.5/§8, specs/007-public-join-links.md §1 — `joinLinkHost` is the
    // 007 deployment constant. H4 (docs/azure-setup.md §7) provisioned the real Static Web App
    // 2026-07-22; `defaultJoinLinkHost` is its real hostname (no Xcode build-config override
    // mechanism exists yet, specs/004 §1.1, so this default is what actually ships).
    @Test func joinLinkHostDefaultsToTheProvisionedHost() {
        #expect(AppConfig().joinLinkHost == AppConfig.defaultJoinLinkHost)
        #expect(AppConfig.defaultJoinLinkHost == "gentle-hill-0fae42f03.7.azurestaticapps.net")
    }

    @Test func joinLinkHostIsConfigurable() {
        let config = AppConfig(joinLinkHost: "swa-findly.azurestaticapps.net")
        #expect(config.joinLinkHost == "swa-findly.azurestaticapps.net")
    }
}
