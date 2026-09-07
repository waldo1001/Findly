import Testing
import Foundation
@testable import FindlyKit

/// I47 (docs/implementation-handoff.md) — `FirebaseAuthProvider.configureFirebaseIfNeeded()`
/// called `FirebaseApp.configure()` with no plist-format validation, so a malformed `API_KEY`
/// raised inside Firebase's own `+[FIRInstallations validateAPIKey:]` and aborted with `SIGABRT`
/// before a single pixel rendered — a stack that is entirely Firebase internals, naming nothing
/// about the plist. `FirebaseAPIKeyValidator` reproduces that exact check in pure, testable Swift
/// so the app target can fail *before* handing control to Firebase, with a message that names the
/// file and the problem instead of an opaque crash.
///
/// The three rules below are copied from the real, linked SDK checkout (verified empirically,
/// not assumed): firebase-ios-sdk 11.15.x,
/// `FirebaseInstallations/Source/Library/FIRInstallations.m`, `+validateAPIKey:` —
/// `kExpectedAPIKeyLength = 39`; the key must start with `"A"`; and it must contain only
/// alphanumeric characters plus `-`/`_` (base64 URL-safe alphabet).
@Suite("FirebaseAPIKeyValidator")
struct FirebaseAPIKeyValidatorTests {

    /// A **fabricated** key satisfying the same format a real one must (39 chars, starts with
    /// "A", base64url charset) — deliberately not copied from any real project's config
    /// (docs/security-review-checklist.md §1: no realistic-looking credential in the repo).
    static let validShapedKey = "ATestFixtureNotARealKey-000000000000001"

    @Test("a well-formed key has no issues")
    func validKeyHasNoIssues() {
        #expect(FirebaseAPIKeyValidator.issues(with: Self.validShapedKey).isEmpty)
        #expect(FirebaseAPIKeyValidator.isValid(Self.validShapedKey))
    }

    @Test("nil is reported as missing")
    func nilKeyIsMissing() {
        let issues = FirebaseAPIKeyValidator.issues(with: nil)
        #expect(!issues.isEmpty)
        #expect(!FirebaseAPIKeyValidator.isValid(nil))
    }

    @Test("empty string is reported as missing")
    func emptyKeyIsMissing() {
        #expect(!FirebaseAPIKeyValidator.isValid(""))
    }

    @Test("wrong length is flagged with the expected length")
    func wrongLengthIsFlagged() {
        let tooShort = "AONLY10CHARS"
        let issues = FirebaseAPIKeyValidator.issues(with: tooShort)
        #expect(issues.contains { $0.contains("39") })
        #expect(!FirebaseAPIKeyValidator.isValid(tooShort))
    }

    @Test("a prefix other than 'A' is flagged")
    func wrongPrefixIsFlagged() {
        // Same length as a real key (39), same charset, but starts with "B".
        let wrongPrefix = "B" + String(Self.validShapedKey.dropFirst())
        #expect(wrongPrefix.count == FirebaseAPIKeyValidator.expectedLength)
        let issues = FirebaseAPIKeyValidator.issues(with: wrongPrefix)
        #expect(issues.contains { $0.localizedCaseInsensitiveContains("start") })
        #expect(!FirebaseAPIKeyValidator.isValid(wrongPrefix))
    }

    @Test("disallowed characters are flagged")
    func disallowedCharactersAreFlagged() {
        // Same length (39), starts with "A", but contains a "!" which base64url never does.
        var chars = Array(Self.validShapedKey)
        chars[10] = "!"
        let withBangChar = String(chars)
        #expect(withBangChar.count == FirebaseAPIKeyValidator.expectedLength)
        let issues = FirebaseAPIKeyValidator.issues(with: withBangChar)
        #expect(issues.contains { $0.localizedCaseInsensitiveContains("character") })
        #expect(!FirebaseAPIKeyValidator.isValid(withBangChar))
    }

    @Test("the historical CI placeholder is correctly rejected on multiple grounds")
    func historicalCIPlaceholderIsRejected() {
        // The literal that crashed three consecutive Simulator-verification attempts (I39, I45,
        // I46) — docs/implementation-handoff.md row I47. Wrong length AND wrong prefix.
        let historicalPlaceholder = "CI-PLACEHOLDER-NOT-A-REAL-API-KEY"
        let issues = FirebaseAPIKeyValidator.issues(with: historicalPlaceholder)
        #expect(issues.count >= 2)
        #expect(!FirebaseAPIKeyValidator.isValid(historicalPlaceholder))
    }

    @Test("the new format-valid CI placeholder passes validation")
    func newCIPlaceholderIsAccepted() {
        // Must stay in sync with .github/workflows/ios.yml's placeholder API_KEY — format-valid
        // (so a placeholder build actually launches) while being unmistakably fake on sight.
        let newPlaceholder = "AFAKE-NOT-REAL-KEY-DO-NOT-USE-IN-PROD00"
        #expect(newPlaceholder.count == FirebaseAPIKeyValidator.expectedLength)
        #expect(FirebaseAPIKeyValidator.isValid(newPlaceholder))
    }
}
