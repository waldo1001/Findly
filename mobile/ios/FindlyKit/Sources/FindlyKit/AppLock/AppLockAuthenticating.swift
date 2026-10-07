import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

public enum AppLockAuthResult: Equatable, Sendable {
    case success
    /// The user (or the system) dismissed the prompt.
    case cancelled
    case failed
}

/// specs/010 §1.4 — the injectable seam in front of `LocalAuthentication`, so unit tests never call
/// the framework. The real implementation is `SystemAppLockAuthenticator`.
@MainActor
public protocol AppLockAuthenticating: AnyObject {
    func capability() -> AppLockCapability
    /// `LAContext.evaluatePolicy(.deviceOwnerAuthentication, …)`: biometrics with passcode fallback.
    func authenticate(reason: String) async -> AppLockAuthResult
}

/// A device that cannot authenticate (used where `LocalAuthentication` is unavailable and as the
/// inert default).
@MainActor
public final class UnavailableAppLockAuthenticator: AppLockAuthenticating {
    public init() {}
    public func capability() -> AppLockCapability { AppLockCapability(canAuthenticate: false, biometry: .none) }
    public func authenticate(reason: String) async -> AppLockAuthResult { .failed }
}

#if canImport(LocalAuthentication)
/// The real `LAContext`-backed authenticator. Not unit-tested (it would call the framework); it is
/// verified by the `xcodebuild` gate (004 §2) and on a device.
@MainActor
public final class SystemAppLockAuthenticator: AppLockAuthenticating {
    public init() {}

    public func capability() -> AppLockCapability {
        let context = LAContext()
        var error: NSError?
        let can = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        let passcodeNotSet = !can && (error as? LAError)?.code == .passcodeNotSet
        // Biometry wording (010 §1.4: "passcode when no biometry is enrolled") comes from a
        // biometrics-only evaluation; `biometryType` is only valid after `canEvaluatePolicy` ran.
        let bioContext = LAContext()
        var biometry = AppLockBiometry.none
        if bioContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            switch bioContext.biometryType {
            case .faceID: biometry = .faceID
            case .touchID: biometry = .touchID
            default:
                if #available(iOS 17.0, macOS 14.0, *), bioContext.biometryType == .opticID { biometry = .opticID }
            }
        }
        return AppLockCapability(canAuthenticate: can, biometry: biometry, passcodeNotSet: passcodeNotSet)
    }

    public func authenticate(reason: String) async -> AppLockAuthResult {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}
#endif
