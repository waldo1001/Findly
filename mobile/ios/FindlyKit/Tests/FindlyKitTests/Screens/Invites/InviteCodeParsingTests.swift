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
}
