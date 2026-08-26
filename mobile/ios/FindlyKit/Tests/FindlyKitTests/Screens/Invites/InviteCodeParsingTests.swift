import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §1.4; security checklist §5 — deep-link inputs validated
/// before use).
struct InviteCodeParsingTests {

    @Test func normalize_acceptsCanonicalUppercaseCode() {
        #expect(InviteCodeParsing.normalize("7F3K9QRZ") == "7F3K9QRZ")
    }

    @Test func normalize_acceptsLowercaseHyphenatedDisplayForm() {
        #expect(InviteCodeParsing.normalize("7f3k-9qrz") == "7F3K9QRZ")
    }

    @Test func normalize_extractsCodeFromDeepLink() {
        #expect(InviteCodeParsing.normalize("findly://invite/7F3K9QRZ") == "7F3K9QRZ")
    }

    @Test func normalize_extractsCodeFromHttpsDeepLink() {
        #expect(InviteCodeParsing.normalize("https://findly.example/invite/7f3k9qrz") == "7F3K9QRZ")
    }

    @Test func normalize_rejectsWrongLength() {
        #expect(InviteCodeParsing.normalize("7F3K9Q") == nil)
        #expect(InviteCodeParsing.normalize("7F3K9QRZXX") == nil)
    }

    @Test func normalize_rejectsAmbiguousCrockfordCharacters() {
        // I, L, O, U are excluded from Crockford base32 (specs/001 §1.4).
        #expect(InviteCodeParsing.normalize("7F3K9QRI") == nil)
        #expect(InviteCodeParsing.normalize("7F3K9QRL") == nil)
        #expect(InviteCodeParsing.normalize("7F3K9QRO") == nil)
        #expect(InviteCodeParsing.normalize("7F3K9QRU") == nil)
    }

    @Test func normalize_rejectsUnrelatedUrl() {
        // A URL-shaped string that isn't our invite deep link must never leak its host/path
        // through as if it were a code.
        #expect(InviteCodeParsing.normalize("https://evil.example/not-an-invite") == nil)
    }

    @Test func normalize_rejectsEmptyString() {
        #expect(InviteCodeParsing.normalize("") == nil)
    }

    @Test func normalize_trimsWhitespace() {
        #expect(InviteCodeParsing.normalize("  7F3K9QRZ  ") == "7F3K9QRZ")
    }

    // MARK: - family-invite deep link (specs/007 §1/§4, added 2026-08-26)

    @Test func normalize_extractsCodeFromFamilyJoinDeepLink() {
        #expect(InviteCodeParsing.normalize("findly://family-join?code=7F3K9QRZ") == "7F3K9QRZ")
    }

    @Test func normalize_extractsAndNormalizesHyphenatedCodeFromFamilyJoinDeepLink() {
        #expect(InviteCodeParsing.normalize("findly://family-join?code=7f3k-9qrz") == "7F3K9QRZ")
    }

    @Test func normalize_rejectsFamilyJoinDeepLinkMissingCodeParam() {
        #expect(InviteCodeParsing.normalize("findly://family-join") == nil)
        #expect(InviteCodeParsing.normalize("findly://family-join?code=") == nil)
    }

    @Test func normalize_rejectsGroupJoinDeepLink() {
        // Same "findly" scheme, different feature — must not cross-parse as an invite code.
        #expect(InviteCodeParsing.normalize("findly://group-join?code=7F3K9QRZ") == nil)
    }
}

/// specs/007-public-join-links.md §1/§4, specs/010-app-shell-and-screen-ux.md §5.2 — the https
/// universal-link form (`https://{joinLinkHost}/f#CODE`), added alongside the `findly://` form
/// above. Mirrors `GroupCodeParsingHttpsLinkTests` exactly (same charset whitelist, same fragment-
/// only privacy rule, same caller-supplied-host invariant).
struct InviteCodeParsingHttpsLinkTests {
    private let host = "join.example.test"

    @Test func matchHttpsInviteLink_acceptsCanonicalUppercaseFragment() {
        let url = URL(string: "https://join.example.test/f#7F3K9QRZ")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .recognized(code: "7F3K9QRZ"))
    }

    @Test func matchHttpsInviteLink_acceptsLowercaseHyphenatedFragment() {
        let url = URL(string: "https://join.example.test/f#7f3k-9qrz")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .recognized(code: "7F3K9QRZ"))
    }

    @Test func matchHttpsInviteLink_rejectsWrongHost() {
        let url = URL(string: "https://evil.example/f#7F3K9QRZ")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsInviteLink_rejectsWrongPath() {
        let url = URL(string: "https://join.example.test/other#7F3K9QRZ")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsInviteLink_rejectsGroupPath() {
        // `/f` never routes to the group screen, nor `/g` to the family one (007 §7).
        let url = URL(string: "https://join.example.test/g#7F3K9QRZ")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsInviteLink_rejectsPathWithTrailingSlash() {
        let url = URL(string: "https://join.example.test/f/#7F3K9QRZ")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsInviteLink_rejectsNonHttpsScheme() {
        let url = URL(string: "findly://join.example.test/f#7F3K9QRZ")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsInviteLink_validHostAndPathButNoFragment_isRecognizedWithNilCode() {
        let url = URL(string: "https://join.example.test/f")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .recognized(code: nil))
    }

    @Test func matchHttpsInviteLink_garbageFragment_isRecognizedWithNilCode() {
        let url = URL(string: "https://join.example.test/f#not-a-valid-code!!")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .recognized(code: nil))
    }

    @Test func matchHttpsInviteLink_rejectsAmbiguousCrockfordCharactersInFragment() {
        let url = URL(string: "https://join.example.test/f#7F3K9QRI")!
        #expect(InviteCodeParsing.matchHttpsInviteLink(url, joinLinkHost: host) == .recognized(code: nil))
    }
}

/// specs/010-app-shell-and-screen-ux.md §5.2 — the smart code field's live-typing formatter.
struct InviteCodeParsingLiveFormatTests {
    @Test func liveFormat_groupsIntoFourAndFour() {
        #expect(InviteCodeParsing.liveFormat("7F3K9QRZ") == "7F3K-9QRZ")
    }

    @Test func liveFormat_uppercasesAsItTypes() {
        #expect(InviteCodeParsing.liveFormat("7f3k9qrz") == "7F3K-9QRZ")
    }

    @Test func liveFormat_stripsHyphensAndSpacesBeforeRegrouping() {
        #expect(InviteCodeParsing.liveFormat("7f3k -9q rz") == "7F3K-9QRZ")
    }

    @Test func liveFormat_whitelistFiltersAmbiguousCrockfordCharacters() {
        // I, L, O, U are excluded (001 §1.4) — typing them must silently drop them, not pass
        // them through as if valid.
        #expect(InviteCodeParsing.liveFormat("7FIL3OKU9QRZ") == "7F3K-9QRZ")
    }

    @Test func liveFormat_neverExceedsEightSignificantCharacters() {
        #expect(InviteCodeParsing.liveFormat("7F3K9QRZXXXXXX") == "7F3K-9QRZ")
    }

    @Test func liveFormat_shortInputIsNotYetHyphenated() {
        #expect(InviteCodeParsing.liveFormat("7F3") == "7F3")
    }

    @Test func liveFormat_emptyInputStaysEmpty() {
        #expect(InviteCodeParsing.liveFormat("") == "")
    }
}
