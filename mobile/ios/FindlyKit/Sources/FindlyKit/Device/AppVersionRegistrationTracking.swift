import Foundation

/// specs/004-ios-client.md §5 — backs the "every app update" re-registration trigger: remembers,
/// per signed-in user (mirrors `DeviceIdProviding`'s per-user keying — a different user signing in
/// on the same device must be treated as ITS OWN first launch, not skipped because a previous
/// user's version happened to match), which `appVersion` was last successfully registered.
public protocol AppVersionRegistrationTracking {
    func lastRegisteredAppVersion(forUserId userId: String) -> String?
    func setLastRegisteredAppVersion(_ version: String, forUserId userId: String)
}

/// Test/dev default.
public final class InMemoryAppVersionRegistrationTracker: AppVersionRegistrationTracking {
    private var versionsByUser: [String: String] = [:]

    public init() {}

    public func lastRegisteredAppVersion(forUserId userId: String) -> String? { versionsByUser[userId] }
    public func setLastRegisteredAppVersion(_ version: String, forUserId userId: String) { versionsByUser[userId] = version }
}

/// Persists across launches via `UserDefaults` — the real device implementation.
public final class UserDefaultsAppVersionRegistrationTracker: AppVersionRegistrationTracking {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastRegisteredAppVersion(forUserId userId: String) -> String? { defaults.string(forKey: key(for: userId)) }
    public func setLastRegisteredAppVersion(_ version: String, forUserId userId: String) { defaults.set(version, forKey: key(for: userId)) }

    private func key(for userId: String) -> String { "FindlyKit.lastRegisteredAppVersion.\(userId)" }
}
