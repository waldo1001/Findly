import Testing
@testable import FindlyKit

/// specs/006-phone-auth.md §4.1, specs/004-ios-client.md §4.1 — the two-step phone sign-in state
/// machine (minus the Android-only instant-verification arrows). `SleepGate`/`waitUntil` are
/// shared test-module helpers defined in LocateViewModelTests.swift / DeviceRegistrationServiceTests.swift.
@MainActor
struct SignInViewModelTests {

    // MARK: - Phone entry / client-side validation

    @Test func initialState_isEnteringPhoneWithNoError() {
        let viewModel = SignInViewModel(authProvider: FakeAuthProviding())
        #expect(viewModel.state == .enteringPhone(error: nil))
    }

    @Test func submitInvalidPhoneNumber_staysOnEnteringPhoneWithError_andMakesNoProviderCall() async {
        let auth = FakeAuthProviding()
        let viewModel = SignInViewModel(authProvider: auth)

        await viewModel.submitPhoneNumber("not-a-number")

        #expect(viewModel.state == .enteringPhone(error: PhoneAuthError.invalidPhoneNumber.userMessage))
        #expect(auth.startPhoneVerificationCalls.isEmpty, "an invalid number must never reach the provider")
    }

    @Test func submitValidPhoneNumber_normalizesBeforeCallingTheProvider() async {
        let auth = FakeAuthProviding()
        let viewModel = SignInViewModel(authProvider: auth)

        await viewModel.submitPhoneNumber("0470 00 00 01")

        #expect(auth.startPhoneVerificationCalls == ["+32470000001"])
        #expect(viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 30, error: nil))
    }

    @Test func submitValidPhoneNumber_transientlyEntersSendingCode() async throws {
        let auth = FakeAuthProviding()
        let gate = SleepGate()
        auth.startPhoneVerificationGate = gate
        let viewModel = SignInViewModel(authProvider: auth)

        let task = Task { await viewModel.submitPhoneNumber("+32470000001") }
        try await waitUntil { viewModel.state == .sendingCode(phone: "+32470000001") }

        await gate.release()
        _ = await task.value
        #expect(viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 30, error: nil))
    }

    @Test func startVerificationFailure_returnsToEnteringPhoneWithTheSpeccedMessage() async {
        for phoneError in PhoneAuthError.allCases {
            let auth = FakeAuthProviding()
            auth.startPhoneVerificationResult = .failure(phoneError)
            let viewModel = SignInViewModel(authProvider: auth)

            await viewModel.submitPhoneNumber("+32470000001")

            #expect(viewModel.state == .enteringPhone(error: phoneError.userMessage), "case \(phoneError)")
        }
    }

    // MARK: - Code entry / confirmation

    @Test func submitCode_happyPath_transitionsToSignedIn_andInvokesOnSignedIn() async {
        let auth = FakeAuthProviding()
        var signedInCalled = false
        let viewModel = SignInViewModel(authProvider: auth, onSignedIn: { signedInCalled = true })

        await viewModel.submitPhoneNumber("+32470000001")
        await viewModel.submitCode("123456")

        #expect(viewModel.state == .signedIn(userId: "+32470000001"))
        #expect(auth.confirmCodeCalls == ["123456"])
        #expect(signedInCalled)
    }

    @Test func submitCode_transientlyEntersConfirmingCode() async throws {
        let auth = FakeAuthProviding()
        let gate = SleepGate()
        let viewModel = SignInViewModel(authProvider: auth)
        await viewModel.submitPhoneNumber("+32470000001")
        auth.confirmCodeGate = gate

        let task = Task { await viewModel.submitCode("123456") }
        try await waitUntil { viewModel.state == .confirmingCode(phone: "+32470000001") }

        await gate.release()
        _ = await task.value
        #expect(viewModel.state == .signedIn(userId: "+32470000001"))
    }

    @Test func submitCode_invalidCode_staysOnEnteringCode_cooldownUnaffected() async {
        let auth = FakeAuthProviding()
        auth.confirmCodeResult = .failure(.invalidCode)
        let viewModel = SignInViewModel(authProvider: auth)
        await viewModel.submitPhoneNumber("+32470000001")

        await viewModel.submitCode("000000")

        #expect(viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 30, error: PhoneAuthError.invalidCode.userMessage))
    }

    @Test func submitCode_codeExpired_returnsToEnteringPhone() async {
        let auth = FakeAuthProviding()
        auth.confirmCodeResult = .failure(.codeExpired)
        let viewModel = SignInViewModel(authProvider: auth)
        await viewModel.submitPhoneNumber("+32470000001")

        await viewModel.submitCode("000000")

        #expect(viewModel.state == .enteringPhone(error: PhoneAuthError.codeExpired.userMessage))
    }

    @Test func submitCode_otherError_staysOnEnteringCode() async {
        let auth = FakeAuthProviding()
        auth.confirmCodeResult = .failure(.network)
        let viewModel = SignInViewModel(authProvider: auth)
        await viewModel.submitPhoneNumber("+32470000001")

        await viewModel.submitCode("000000")

        #expect(viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 30, error: PhoneAuthError.network.userMessage))
    }

    // MARK: - Change number

    @Test func changeNumber_fromEnteringCode_returnsToEnteringPhone() async {
        let auth = FakeAuthProviding()
        let viewModel = SignInViewModel(authProvider: auth)
        await viewModel.submitPhoneNumber("+32470000001")

        viewModel.changeNumber()

        #expect(viewModel.state == .enteringPhone(error: nil))
    }

    // MARK: - Resend / cooldown (virtual time)

    @Test func resend_blockedUntilCooldownReachesZero_thenReinvokesStartVerificationExactlyOnce() async throws {
        let auth = FakeAuthProviding()
        let gate = SleepGate()
        let viewModel = SignInViewModel(authProvider: auth, resendCooldownSeconds: 2, sleep: { _ in await gate.wait() })

        await viewModel.submitPhoneNumber("+32470000001")
        #expect(viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 2, error: nil))
        #expect(auth.startPhoneVerificationCalls == ["+32470000001"])

        // Blocked at 2s left.
        await viewModel.resend()
        #expect(auth.startPhoneVerificationCalls.count == 1)

        await gate.release()
        try await waitUntil { viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 1, error: nil) }

        // Still blocked at 1s left.
        await viewModel.resend()
        #expect(auth.startPhoneVerificationCalls.count == 1)

        await gate.release()
        try await waitUntil { viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 0, error: nil) }

        // Unblocked at 0s left: exactly one more start-verification call, same number.
        await viewModel.resend()
        #expect(auth.startPhoneVerificationCalls == ["+32470000001", "+32470000001"])
        #expect(viewModel.state == .enteringCode(phone: "+32470000001", resendSecondsLeft: 2, error: nil), "cooldown restarts on a successful resend")
    }
}

/// A controllable `AuthProviding` fake: `startPhoneVerification`/`confirmCode` succeed by default
/// (recording the call), optionally fail with an injected `PhoneAuthError`, and optionally suspend
/// on a `SleepGate` so a test can observe the caller's transient state before releasing them —
/// same technique as `LocateViewModelTests`' `SleepGate`-driven poll-loop tests.
final class FakeAuthProviding: AuthProviding {
    var currentUserId: String?
    var startPhoneVerificationResult: Result<Void, PhoneAuthError> = .success(())
    var confirmCodeResult: Result<Void, PhoneAuthError> = .success(())
    var startPhoneVerificationGate: SleepGate?
    var confirmCodeGate: SleepGate?
    private(set) var startPhoneVerificationCalls: [String] = []
    private(set) var confirmCodeCalls: [String] = []
    private var lastPhoneNumber: String?

    func currentIDToken() async throws -> String { "fake-token" }
    func refreshIDToken() async throws -> String { "fake-token" }
    func signOut() throws { currentUserId = nil }

    func startPhoneVerification(phoneNumberE164: String) async throws {
        if let gate = startPhoneVerificationGate {
            await gate.wait()
        }
        startPhoneVerificationCalls.append(phoneNumberE164)
        lastPhoneNumber = phoneNumberE164
        try startPhoneVerificationResult.get()
    }

    func confirmCode(_ code: String) async throws {
        if let gate = confirmCodeGate {
            await gate.wait()
        }
        confirmCodeCalls.append(code)
        try confirmCodeResult.get()
        currentUserId = lastPhoneNumber
    }
}
