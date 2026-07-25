import Foundation

/// specs/004-ios-client.md §5, specs/001 §1.4 — a client-generated UUIDv4 `deviceId`, stable per
/// signed-in user, fresh whenever the signed-in user changes.
public protocol DeviceIdProviding: AnyObject {
    func deviceId(forUserId userId: String) -> String
    func clearDeviceId(forUserId userId: String)
}

/// In-memory implementation — dev/test default and the base for `UserDefaultsDeviceIdProvider`'s
/// persistence semantics.
public final class InMemoryDeviceIdProvider: DeviceIdProviding {
    private var idsByUser: [String: String] = [:]
    private let generateUUID: () -> String

    public init(generateUUID: @escaping () -> String = { UUID().uuidString }) {
        self.generateUUID = generateUUID
    }

    public func deviceId(forUserId userId: String) -> String {
        if let existing = idsByUser[userId] { return existing }
        let fresh = generateUUID()
        idsByUser[userId] = fresh
        return fresh
    }

    public func clearDeviceId(forUserId userId: String) {
        idsByUser[userId] = nil
    }
}

/// Persists across launches via `UserDefaults` — the real device/app implementation.
public final class UserDefaultsDeviceIdProvider: DeviceIdProviding {
    private let defaults: UserDefaults
    private let generateUUID: () -> String

    public init(defaults: UserDefaults = .standard, generateUUID: @escaping () -> String = { UUID().uuidString }) {
        self.defaults = defaults
        self.generateUUID = generateUUID
    }

    public func deviceId(forUserId userId: String) -> String {
        let key = storageKey(for: userId)
        if let existing = defaults.string(forKey: key) { return existing }
        let fresh = generateUUID()
        defaults.set(fresh, forKey: key)
        return fresh
    }

    public func clearDeviceId(forUserId userId: String) {
        defaults.removeObject(forKey: storageKey(for: userId))
    }

    private func storageKey(for userId: String) -> String {
        "FindlyKit.deviceId.\(userId)"
    }
}
