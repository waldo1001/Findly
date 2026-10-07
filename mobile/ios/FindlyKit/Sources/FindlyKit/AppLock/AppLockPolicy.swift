import Foundation

/// specs/010-app-shell-and-screen-ux.md §1.4 (I20-followup / 000 §D20, row I64) — the pure app-lock
/// decisions. No I/O, no clock of its own, no `LocalAuthentication`: unit-testable on any host.
public enum AppLockPolicy {
    /// 010 §1.4 "return to the foreground after ≥ 5 minutes in the background".
    public static let backgroundThreshold: TimeInterval = 300

    /// 010 §1.4 "When it locks" — `shouldLock(enabled, signedIn, isColdStart, backgroundedAt, now)`.
    ///
    /// Only while enabled and signed in. A cold start always locks; a foreground return locks only
    /// after `backgroundThreshold` in the background. A `backgroundedAt` in the future (the clock
    /// moved backwards) cannot be aged, and failing open there would let a clock change defeat the
    /// lock — so it locks.
    public static func shouldLock(
        enabled: Bool, signedIn: Bool, isColdStart: Bool, backgroundedAt: Date?, now: Date
    ) -> Bool {
        guard enabled, signedIn else { return false }
        if isColdStart { return true }
        guard let backgroundedAt else { return false }
        let age = now.timeIntervalSince(backgroundedAt)
        return age < 0 || age >= backgroundThreshold
    }
}

/// `LAContext.biometryType`, minus the framework.
public enum AppLockBiometry: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    /// No biometry enrolled — the device passcode is the only credential.
    case none
}

/// What the device can do for the lock right now (`LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)`).
public struct AppLockCapability: Equatable, Sendable {
    public var canAuthenticate: Bool
    public var biometry: AppLockBiometry

    public init(canAuthenticate: Bool, biometry: AppLockBiometry) {
        self.canAuthenticate = canAuthenticate
        self.biometry = biometry
    }
}

/// 010 §1.4 "Setting" / "Enabling" — what the Privacy & data toggle shows.
public struct AppLockToggleState: Equatable, Sendable {
    public let label: String
    public let isInteractive: Bool
    public let caption: String?

    public static let unavailableCaption = "Set a screen lock on this phone first."

    /// The label follows the biometry type. The toggle is enabled only when the device can
    /// authenticate the owner — otherwise it is disabled with the caption. A lock that is already
    /// ON stays interactive even if the device credential has since vanished: switching off needs
    /// no authentication, and the user must never be unable to turn it off.
    public static func make(capability: AppLockCapability, isEnabled: Bool) -> AppLockToggleState {
        let method: String
        switch capability.biometry {
        case .faceID: method = "Face ID"
        case .touchID: method = "Touch ID"
        case .opticID: method = "Optic ID"
        case .none: method = "passcode"
        }
        let interactive = capability.canAuthenticate || isEnabled
        return AppLockToggleState(
            label: "Require \(method) to open Findly",
            isInteractive: interactive,
            caption: interactive ? nil : unavailableCaption
        )
    }
}
