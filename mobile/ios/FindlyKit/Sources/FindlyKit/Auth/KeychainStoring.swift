import Foundation

/// I7 hardening (docs/implementation-handoff.md "Known follow-ups"; specs/004-ios-client.md §4.1) —
/// abstracts the secure string storage `FirebaseAuthProvider` (app target) needs for the Firebase
/// phone-verification session id (`verificationID`), so the provider stays testable without a real
/// Keychain in unit tests. Mirrors this codebase's existing protocol-abstracts-the-OS-dependency
/// idiom (`DeviceIdProviding`, `LocationProviding`): a small OS-facing contract here, with the real
/// `Security`-framework-backed implementation living in the app target (`Findly/Auth/`) — kept
/// out of `FindlyKit` because Keychain access doesn't behave deterministically in a headless
/// `swift test` sandbox (no guaranteed unlocked keychain / access-group entitlements), the same
/// reason `FirebaseAuthProvider` itself is app-target-only.
///
/// The method names mirror `UserDefaults`' own (`string(forKey:)` / `set(_:forKey:)`) so swapping
/// the underlying store is a minimal diff at call sites previously written against `UserDefaults`.
public protocol KeychainStoring: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
    func removeString(forKey key: String)
}

/// In-memory implementation — dev/test default. The real device implementation
/// (`KeychainStore`) lives in the app target; see `KeychainStoring`'s doc comment for why.
public final class InMemoryKeychainStore: KeychainStoring {
    private var valuesByKey: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        valuesByKey[key]
    }

    public func setString(_ value: String, forKey key: String) {
        valuesByKey[key] = value
    }

    public func removeString(forKey key: String) {
        valuesByKey[key] = nil
    }
}
