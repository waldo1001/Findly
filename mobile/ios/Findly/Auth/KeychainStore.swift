import Foundation
import Security
import FindlyKit

/// I7 hardening (docs/implementation-handoff.md "Known follow-ups": iOS `verificationID` stored in
/// `UserDefaults`, not Keychain) — the real `KeychainStoring` implementation, backed by the
/// `Security` framework's generic-password Keychain item type. Lives in the app target, not
/// `FindlyKit` (see `KeychainStoring`'s doc comment for why), so it is verified via `swiftc
/// -typecheck` against the built `FindlyKit` module rather than a real `swift test` run.
///
/// Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the item (a) is only readable
/// while the device is unlocked (matches its lifetime: it only needs to exist between "start phone
/// verification" and "confirm code", both foreground user actions), (b) is excluded from iCloud
/// Keychain sync and from the *data* restored to a **different** device from an encrypted backup —
/// appropriate for a value that is meaningless off the device that started the verification (it is
/// a Firebase session handle, not a durable credential). This is at least as strict as the
/// `UserDefaults` storage it replaces (plaintext, no accessibility restriction at all), never
/// weaker, so this migration cannot introduce a "worse than before" persistence-across-reinstall
/// behavior.
final class KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.findly.ios") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String, forKey key: String) {
        // Delete-then-add keeps write semantics simple (no partial-attribute SecItemUpdate
        // dictionary to get right) and matches this type's only actual usage pattern: whole-value
        // replacement, never a partial update.
        removeString(forKey: key)

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func removeString(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
