import Testing
@testable import FindlyKit

/// specs/006-phone-auth.md §4.2 — the closed, fixed v1 error → user-message mapping. Raw SDK text
/// must never reach a screen; every `PhoneAuthError` case has exactly one fixed English message.
struct PhoneAuthUserMessageTests {

    @Test func everyErrorCase_mapsToItsSpeccedMessage() {
        #expect(PhoneAuthError.invalidPhoneNumber.userMessage == "That doesn't look like a valid phone number.")
        #expect(PhoneAuthError.tooManyRequests.userMessage == "Too many attempts. Wait a while and try again.")
        #expect(PhoneAuthError.smsQuotaExceeded.userMessage == "SMS limit reached for now. Try again later.")
        #expect(PhoneAuthError.appVerificationFailed.userMessage == "Couldn't verify this device. Update the app and try again.")
        #expect(PhoneAuthError.invalidCode.userMessage == "That code isn't right. Check the SMS and try again.")
        #expect(PhoneAuthError.codeExpired.userMessage == "That code expired. Request a new one.")
        #expect(PhoneAuthError.network.userMessage == "No connection. Check your network and try again.")
        #expect(PhoneAuthError.unknown.userMessage == "Couldn't sign in. Try again.")
    }

    @Test func nonPhoneAuthError_getsTheGenericUnknownFallback() {
        struct SomeOtherError: Error {}
        #expect(phoneAuthUserMessage(for: SomeOtherError()) == PhoneAuthError.unknown.userMessage)
    }
}
