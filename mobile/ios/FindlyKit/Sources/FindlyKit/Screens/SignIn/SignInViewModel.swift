import Foundation

/// specs/006-phone-auth.md §4.1, specs/004-ios-client.md §4.1 — the two-step phone sign-in state
/// machine, normative for both platforms minus the Android-only instant-verification arrows (004
/// §4.1: "iOS has no instant verification, so plain async methods suffice").
public enum SignInState: Equatable {
    case enteringPhone(error: String?)
    case sendingCode(phone: String)
    case enteringCode(phone: String, resendSecondsLeft: Int, error: String?)
    case confirmingCode(phone: String)
    case signedIn(userId: String)
}

@MainActor
public final class SignInViewModel: ObservableObject {
    @Published public private(set) var state: SignInState = .enteringPhone(error: nil)

    private let authProvider: AuthProviding
    private let onSignedIn: (() -> Void)?
    private let resendCooldownSeconds: Int
    /// Injectable so the 30 s resend cooldown (006 §4.1) advances deterministically in tests
    /// instead of racing a real timer — same pattern as `LocateViewModel`'s poll loop.
    private let sleep: (Duration) async -> Void

    private var cooldownTask: Task<Void, Never>?

    public init(
        authProvider: AuthProviding,
        onSignedIn: (() -> Void)? = nil,
        resendCooldownSeconds: Int = 30,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.authProvider = authProvider
        self.onSignedIn = onSignedIn
        self.resendCooldownSeconds = resendCooldownSeconds
        self.sleep = sleep
    }

    /// `EnteringPhone` submit: normalize (006 §3), then either reject client-side (no provider
    /// call) or start verification.
    public func submitPhoneNumber(_ rawInput: String) async {
        guard case .enteringPhone = state else { return }
        guard let normalized = PhoneNumberNormalizer.normalize(rawInput) else {
            state = .enteringPhone(error: PhoneAuthError.invalidPhoneNumber.userMessage)
            return
        }
        await startVerification(phone: normalized)
    }

    /// `EnteringCode` submit: confirm the code for the in-flight verification.
    public func submitCode(_ code: String) async {
        guard case .enteringCode(let phone, let resendSecondsLeft, _) = state else { return }
        state = .confirmingCode(phone: phone)
        do {
            try await authProvider.confirmCode(code)
            cooldownTask?.cancel()
            guard let userId = authProvider.currentUserId else {
                // Should not happen (confirmCode succeeded but left no signed-in user) — treat as
                // an unknown failure rather than crash; stay on code entry.
                state = .enteringCode(phone: phone, resendSecondsLeft: resendSecondsLeft, error: PhoneAuthError.unknown.userMessage)
                return
            }
            state = .signedIn(userId: userId)
            onSignedIn?()
        } catch {
            let message = phoneAuthUserMessage(for: error)
            if (error as? PhoneAuthError) == .codeExpired {
                // CODE_EXPIRED: must request a new code.
                cooldownTask?.cancel()
                state = .enteringPhone(error: message)
            } else {
                // INVALID_CODE and any other error: stay on code entry, cooldown unaffected.
                state = .enteringCode(phone: phone, resendSecondsLeft: resendSecondsLeft, error: message)
            }
        }
    }

    /// Resend: only valid once the cooldown has reached 0. Re-invokes start-verification with the
    /// same number (a resend, provider-internal).
    public func resend() async {
        guard case .enteringCode(let phone, let resendSecondsLeft, _) = state, resendSecondsLeft == 0 else { return }
        await startVerification(phone: phone)
    }

    /// Change number: only valid from `EnteringCode`, returns to a fresh `EnteringPhone`.
    public func changeNumber() {
        guard case .enteringCode = state else { return }
        cooldownTask?.cancel()
        state = .enteringPhone(error: nil)
    }

    private func startVerification(phone: String) async {
        cooldownTask?.cancel()
        state = .sendingCode(phone: phone)
        do {
            try await authProvider.startPhoneVerification(phoneNumberE164: phone)
            beginCooldown(phone: phone)
        } catch {
            state = .enteringPhone(error: phoneAuthUserMessage(for: error))
        }
    }

    private func beginCooldown(phone: String) {
        state = .enteringCode(phone: phone, resendSecondsLeft: resendCooldownSeconds, error: nil)
        var remaining = resendCooldownSeconds
        cooldownTask = Task { [weak self] in
            guard let self else { return }
            while remaining > 0 {
                await self.sleep(.seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                if case .enteringCode(let currentPhone, _, let error) = self.state, currentPhone == phone {
                    self.state = .enteringCode(phone: phone, resendSecondsLeft: remaining, error: error)
                }
            }
        }
    }
}
