import Testing
import Foundation
@testable import FindlyKit

/// specs/004-ios-client.md §8 — the app target injects real deployment values through its
/// `Info.plist`; `AppConfig` reads them here. Before this existed, `FindlyApp.init()` called
/// `AppConfig()` with no arguments, so the shipped TestFlight build ran against
/// `https://api.findly.invalid/api/v1` with `authMode == .stubLocal` — it could never reach
/// `func-findly`, and sign-in was faked locally by `StubAuthProvider`.
@Suite("AppConfig from Info.plist")
struct AppConfigInfoDictionaryTests {

    @Test("reads every injected value")
    func readsAllValues() {
        let config = AppConfig(infoDictionary: [
            "FindlyBaseURL": "https://func-findly.azurewebsites.net/api/v1",
            "FindlyAuthMode": "firebase",
            "FindlyFirebaseProjectId": "findly-71f7b",
            "FindlyJoinLinkHost": "example.test",
        ])
        #expect(config.baseURL.absoluteString == "https://func-findly.azurewebsites.net/api/v1")
        #expect(config.authMode == .firebase)
        #expect(config.firebaseProjectId == "findly-71f7b")
        #expect(config.joinLinkHost == "example.test")
    }

    @Test("falls back to safe defaults when keys are absent")
    func missingKeysFallBack() {
        let config = AppConfig(infoDictionary: [:])
        #expect(config.baseURL == AppConfig.placeholderBaseURL)
        #expect(config.authMode == .stubLocal)
        #expect(config.firebaseProjectId == "findly-dev")
        #expect(config.joinLinkHost == AppConfig.defaultJoinLinkHost)
    }

    @Test("a nil info dictionary is treated as absent, not a crash")
    func nilDictionary() {
        let config = AppConfig(infoDictionary: nil)
        #expect(config.baseURL == AppConfig.placeholderBaseURL)
        #expect(config.authMode == .stubLocal)
    }

    /// Xcode leaves unsubstituted `$(VAR)` placeholders in Info.plist when a build setting is
    /// missing — those must not be mistaken for a real value.
    @Test("empty and placeholder-ish strings fall back rather than shipping garbage")
    func emptyStringsFallBack() {
        let config = AppConfig(infoDictionary: [
            "FindlyBaseURL": "",
            "FindlyFirebaseProjectId": "",
            "FindlyJoinLinkHost": "",
        ])
        #expect(config.baseURL == AppConfig.placeholderBaseURL)
        #expect(config.firebaseProjectId == "findly-dev")
        #expect(config.joinLinkHost == AppConfig.defaultJoinLinkHost)
    }

    @Test("only an explicit 'firebase' selects Firebase auth")
    func authModeParsing() {
        #expect(AppConfig(infoDictionary: ["FindlyAuthMode": "firebase"]).authMode == .firebase)
        #expect(AppConfig(infoDictionary: ["FindlyAuthMode": "Firebase"]).authMode == .firebase)
        #expect(AppConfig(infoDictionary: ["FindlyAuthMode": "stubLocal"]).authMode == .stubLocal)
        #expect(AppConfig(infoDictionary: ["FindlyAuthMode": "nonsense"]).authMode == .stubLocal)
        #expect(AppConfig(infoDictionary: [:]).authMode == .stubLocal)
    }

    @Test("an unparseable URL falls back instead of crashing")
    func invalidURLFallsBack() {
        let config = AppConfig(infoDictionary: ["FindlyBaseURL": "not a url at all"])
        #expect(config.baseURL == AppConfig.placeholderBaseURL)
    }
}
