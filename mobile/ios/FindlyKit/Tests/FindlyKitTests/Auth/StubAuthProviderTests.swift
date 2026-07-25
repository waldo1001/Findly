import Foundation
import Testing
@testable import FindlyKit

/// specs/006-phone-auth.md §5, specs/004-ios-client.md §4 — the dev/test `AuthProviding`
/// implementation, phone-shaped: two-step verification (start → confirm) and a **real** unsigned
/// JWT (base64url JSON header/payload, empty signature) matching the backend's
/// `AUTH_MODE=insecure-local` verifier (`InsecureLocalTokenVerifier`, which requires `token.split(".")`
/// to yield a base64url-JSON `parts[1]` with a non-empty string `sub`) — the previous
/// `"stub-header.…"` shape could not be parsed by that verifier.
struct StubAuthProviderTests {

    @Test func startPhoneVerification_thenConfirmCode_signsInWithNormalizedNumberAsUid() async throws {
        let provider = StubAuthProvider()
        #expect(provider.currentUserId == nil)

        try await provider.startPhoneVerification(phoneNumberE164: "+32470000001")
        #expect(provider.currentUserId == nil, "not signed in until the code is confirmed")

        try await provider.confirmCode("123456")
        #expect(provider.currentUserId == "+32470000001")
    }

    @Test func confirmCode_acceptsAnyNonBlankCode() async throws {
        let provider = StubAuthProvider()
        try await provider.startPhoneVerification(phoneNumberE164: "+32470000002")
        try await provider.confirmCode("x")
        #expect(provider.currentUserId == "+32470000002")
    }

    @Test func confirmCode_rejectsABlankCode() async throws {
        let provider = StubAuthProvider()
        try await provider.startPhoneVerification(phoneNumberE164: "+32470000003")
        do {
            try await provider.confirmCode("   ")
            Issue.record("expected PhoneAuthError.invalidCode")
        } catch let error as PhoneAuthError {
            #expect(error == .invalidCode)
        }
        #expect(provider.currentUserId == nil)
    }

    @Test func confirmCode_withNoVerificationInFlight_throwsCodeExpired() async throws {
        // No prior startPhoneVerification call — matches Android's DevAuthProvider/FirebaseAuthProvider
        // (already merged, specs/006 §5/§4.2): "no session to confirm" reads as CODE_EXPIRED, which
        // routes the ViewModel back to phone entry ("must request a new code"), not a generic UNKNOWN.
        let provider = StubAuthProvider()
        do {
            try await provider.confirmCode("123456")
            Issue.record("expected PhoneAuthError.codeExpired")
        } catch let error as PhoneAuthError {
            #expect(error == .codeExpired)
        }
    }

    @Test func startPhoneVerification_defensivelyRevalidatesTheNumber_throwsInvalidPhoneNumberIfUnnormalizable() async throws {
        // Callers (SignInViewModel) are expected to already have normalized the number (006 §3)
        // before calling this — this is a defensive re-check, matching Android's DevAuthProvider.
        let provider = StubAuthProvider()
        do {
            try await provider.startPhoneVerification(phoneNumberE164: "not-a-number")
            Issue.record("expected PhoneAuthError.invalidPhoneNumber")
        } catch let error as PhoneAuthError {
            #expect(error == .invalidPhoneNumber)
        }
    }

    @Test func currentIDToken_throwsWhenNotSignedIn() async throws {
        let provider = StubAuthProvider()
        do {
            _ = try await provider.currentIDToken()
            Issue.record("expected AuthError.notSignedIn")
        } catch let error as AuthError {
            #expect(error == .notSignedIn)
        }
    }

    @Test func signOut_clearsCurrentUserId() async throws {
        let provider = StubAuthProvider(currentUserId: "+32470000004")
        try provider.signOut()
        #expect(provider.currentUserId == nil)
    }

    @Test func refreshIDToken_yieldsADifferentTokenThanBefore() async throws {
        let provider = StubAuthProvider(currentUserId: "+32470000005")
        let first = try await provider.currentIDToken()
        let refreshed = try await provider.refreshIDToken()
        #expect(first != refreshed)
        // Subsequent reads reflect the refreshed token until refreshed again.
        let again = try await provider.currentIDToken()
        #expect(again == refreshed)
    }

    @Test func currentIDToken_isAnUnsignedJWT_parseableByTheInsecureLocalVerifierShape() async throws {
        let provider = StubAuthProvider(currentUserId: "+32470000006", firebaseProjectId: "test-project")
        let token = try await provider.currentIDToken()

        let parts = token.components(separatedBy: ".")
        #expect(parts.count == 3, "header.payload.signature shape")
        #expect(parts[2].isEmpty, "unsigned: the signature segment MUST be empty")

        let payload = try #require(Self.decodeBase64URLJSON(parts[1]))
        #expect(payload["sub"] as? String == "+32470000006")
        #expect(payload["iss"] as? String == "https://securetoken.google.com/test-project")
        #expect(payload["aud"] as? String == "test-project")
        #expect(payload["iat"] != nil)
        #expect(payload["exp"] != nil)
    }

    /// Mirrors what `InsecureLocalTokenVerifier` (backend/src/adapters/auth/firebaseJoseVerifier.ts)
    /// actually does: split on ".", base64url-decode parts[1], JSON.parse it.
    private static func decodeBase64URLJSON(_ segment: String) -> [String: Any]? {
        var base64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
