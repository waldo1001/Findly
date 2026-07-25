import Testing
@testable import FindlyKit

/// specs/006-phone-auth.md §3 — pure E.164 normalization, identical rules to Android's. Applied
/// to user input before any provider call; invalid input is rejected client-side with no provider
/// call ever made (that "no provider call" invariant is exercised at the `SignInViewModel` layer,
/// specs/004 §4.1 — this suite covers only the pure function).
struct PhoneNumberNormalizerTests {

    @Test func stripsSpacesDashesDotsAndParentheses() {
        #expect(PhoneNumberNormalizer.normalize("+32 470 00 00 01") == "+32470000001")
        #expect(PhoneNumberNormalizer.normalize("+32-470-00-00-01") == "+32470000001")
        #expect(PhoneNumberNormalizer.normalize("+32.470.00.00.01") == "+32470000001")
        #expect(PhoneNumberNormalizer.normalize("+32 (470) 00 00 01") == "+32470000001")
    }

    @Test func leadingDoubleZeroBecomesPlus() {
        #expect(PhoneNumberNormalizer.normalize("0032470000001") == "+32470000001")
    }

    @Test func leadingSingleZeroWithNoPlusBecomesPlus32() {
        #expect(PhoneNumberNormalizer.normalize("0470000001") == "+32470000001")
    }

    @Test func alreadyPlusPrefixedInputIsUntouched() {
        #expect(PhoneNumberNormalizer.normalize("+32470000001") == "+32470000001")
        #expect(PhoneNumberNormalizer.normalize("+15550001234") == "+15550001234")
    }

    @Test func validE164AcceptanceEdgeCases() {
        // Minimum length: leading digit + 6 more = 7 digits after the '+'.
        #expect(PhoneNumberNormalizer.normalize("+1234567") == "+1234567")
        // Maximum length: leading digit + 14 more = 15 digits after the '+'.
        #expect(PhoneNumberNormalizer.normalize("+123456789012345") == "+123456789012345")
    }

    @Test func invalidInputIsRejected_returnsNil() {
        // Leading zero right after '+' is not a valid E.164 first digit.
        #expect(PhoneNumberNormalizer.normalize("+0470000001") == nil)
        // Too short (fewer than 7 digits after '+').
        #expect(PhoneNumberNormalizer.normalize("+123456") == nil)
        // Too long (more than 15 digits after '+').
        #expect(PhoneNumberNormalizer.normalize("+1234567890123456") == nil)
        // Empty input.
        #expect(PhoneNumberNormalizer.normalize("") == nil)
        // Letters never form a valid number.
        #expect(PhoneNumberNormalizer.normalize("+32abcxyz01") == nil)
        // A lone "0" cannot become valid E.164 after the +32 substitution (too short).
        #expect(PhoneNumberNormalizer.normalize("0") == nil)
    }
}
