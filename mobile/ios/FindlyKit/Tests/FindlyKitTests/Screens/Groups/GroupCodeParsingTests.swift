import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4/§3.5 (specs/005-temporary-groups.md §1; specs/007-public-join-
/// links.md §1/§4; 001 §1.4; docs/security-review-checklist.md §5 — deep-link inputs validated
/// before use). Group join codes share the invite codes' 8-char Crockford base32 format/
/// normalization (001 §1.4). Two deep-link shapes are recognized: `findly://group-join?code=…` (a
/// query parameter, covered by `normalize(_:)` below) and, since 007, the https universal link
/// `https://{joinLinkHost}/g#CODE` (code in the URL **fragment**, never path/query — covered by
/// `matchHttpsJoinLink(_:joinLinkHost:)` in `GroupCodeParsingHttpsLinkTests` below). `normalize(_:)`
/// itself never accepts raw https text — host-aware validation needs the caller-supplied
/// `joinLinkHost`, which a single-string API has no way to receive, so trusting an arbitrary host
/// there would defeat the "wrong host is ignored, never mis-routed" invariant.
struct GroupCodeParsingTests {

    @Test func normalize_acceptsCanonicalUppercaseCode() {
        #expect(GroupCodeParsing.normalize("7F3K9QRZ") == "7F3K9QRZ")
    }

    @Test func normalize_acceptsLowercaseHyphenatedDisplayForm() {
        #expect(GroupCodeParsing.normalize("7f3k-9qrz") == "7F3K9QRZ")
    }

    @Test func normalize_extractsCodeFromGroupJoinDeepLink() {
        #expect(GroupCodeParsing.normalize("findly://group-join?code=7F3K9QRZ") == "7F3K9QRZ")
    }

    @Test func normalize_extractsAndNormalizesHyphenatedCodeFromDeepLink() {
        #expect(GroupCodeParsing.normalize("findly://group-join?code=7f3k-9qrz") == "7F3K9QRZ")
    }

    @Test func normalize_rejectsWrongLength() {
        #expect(GroupCodeParsing.normalize("7F3K9Q") == nil)
        #expect(GroupCodeParsing.normalize("7F3K9QRZXX") == nil)
    }

    @Test func normalize_rejectsAmbiguousCrockfordCharacters() {
        // I, L, O, U are excluded from Crockford base32 (specs/001 §1.4).
        #expect(GroupCodeParsing.normalize("7F3K9QRI") == nil)
        #expect(GroupCodeParsing.normalize("7F3K9QRL") == nil)
        #expect(GroupCodeParsing.normalize("7F3K9QRO") == nil)
        #expect(GroupCodeParsing.normalize("7F3K9QRU") == nil)
    }

    @Test func normalize_rejectsUnrelatedUrl() {
        // A URL-shaped string that isn't our group-join deep link must never leak its host/path
        // through as if it were a code.
        #expect(GroupCodeParsing.normalize("https://evil.example/not-a-group") == nil)
    }

    @Test func normalize_rejectsInviteDeepLink() {
        // Same "findly" scheme, different feature — must not cross-parse as a group code.
        #expect(GroupCodeParsing.normalize("findly://invite/7F3K9QRZ") == nil)
    }

    @Test func normalize_rejectsHttpsUniversalLink() {
        // `normalize(_:)` is a single-string API with no way to receive an expected host, so it
        // must never trust an arbitrary https host — that's `matchHttpsJoinLink(_:joinLinkHost:)`'s
        // job (specs/007 §1/§4), tested separately below.
        #expect(GroupCodeParsing.normalize("https://findly.example/group-join?code=7F3K9QRZ") == nil)
    }

    @Test func normalize_rejectsDeepLinkMissingCodeParam() {
        #expect(GroupCodeParsing.normalize("findly://group-join") == nil)
        #expect(GroupCodeParsing.normalize("findly://group-join?code=") == nil)
    }

    @Test func normalize_rejectsEmptyString() {
        #expect(GroupCodeParsing.normalize("") == nil)
    }

    @Test func normalize_trimsWhitespace() {
        #expect(GroupCodeParsing.normalize("  7F3K9QRZ  ") == "7F3K9QRZ")
    }
}

/// specs/007-public-join-links.md §1/§4, specs/004-ios-client.md §3.5 — the https universal-link
/// form (`https://{joinLinkHost}/g#CODE`) added alongside the `findly://` form above. `joinLinkHost`
/// is always caller-supplied (never inferred from the URL) so a look-alike host can never be
/// mistaken for the real one; the code lives in the URL **fragment** (`URLComponents.fragment`),
/// never the path or query — the load-bearing privacy property that keeps the join capability out
/// of every server/CDN log by construction (007 §1). Reuses `normalize(_:)`'s exact charset
/// whitelist on the extracted fragment, so there is no second, divergent validation path.
struct GroupCodeParsingHttpsLinkTests {
    private let host = "join.example.test"

    @Test func matchHttpsJoinLink_acceptsCanonicalUppercaseFragment() {
        let url = URL(string: "https://join.example.test/g#7F3K9QRZ")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .recognized(code: "7F3K9QRZ"))
    }

    @Test func matchHttpsJoinLink_acceptsLowercaseHyphenatedFragment() {
        let url = URL(string: "https://join.example.test/g#7f3k-9qrz")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .recognized(code: "7F3K9QRZ"))
    }

    @Test func matchHttpsJoinLink_rejectsWrongHost() {
        // Never mis-routed: a wrong host must be `.notRecognized`, not silently treated as a
        // recognized-but-codeless link.
        let url = URL(string: "https://evil.example/g#7F3K9QRZ")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsJoinLink_rejectsWrongPath() {
        // The path MUST be exactly `/g` (007 §1).
        let url = URL(string: "https://join.example.test/other#7F3K9QRZ")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsJoinLink_rejectsPathWithTrailingSlash() {
        let url = URL(string: "https://join.example.test/g/#7F3K9QRZ")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsJoinLink_rejectsNonHttpsScheme() {
        // The `findly://` scheme is a wholly different code path (`normalize(_:)`) — a `findly://`
        // URL passed here (wrong API for that scheme) must never be recognized.
        let url = URL(string: "findly://join.example.test/g#7F3K9QRZ")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .notRecognized)
    }

    @Test func matchHttpsJoinLink_validHostAndPathButNoFragment_isRecognizedWithNilCode() {
        // 007 §4 / 003 §12.3 verbatim: "a valid link with no usable fragment opens the join screen
        // with an empty code field" — recognized (so the caller DOES route), but no code to prefill.
        let url = URL(string: "https://join.example.test/g")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .recognized(code: nil))
    }

    @Test func matchHttpsJoinLink_emptyFragment_isRecognizedWithNilCode() {
        let url = URL(string: "https://join.example.test/g#")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .recognized(code: nil))
    }

    @Test func matchHttpsJoinLink_garbageFragment_isRecognizedWithNilCode() {
        // 007 §7: "empty/garbage fragment (→ join screen without prefill, no error state)" — a
        // malformed fragment is treated exactly like a missing one, never surfaced as an error.
        let url = URL(string: "https://join.example.test/g#not-a-valid-code!!")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .recognized(code: nil))
    }

    @Test func matchHttpsJoinLink_rejectsAmbiguousCrockfordCharactersInFragment() {
        // Same whitelist as `normalize(_:)` — I/L/O/U are excluded (001 §1.4).
        let url = URL(string: "https://join.example.test/g#7F3K9QRI")!
        #expect(GroupCodeParsing.matchHttpsJoinLink(url, joinLinkHost: host) == .recognized(code: nil))
    }
}
