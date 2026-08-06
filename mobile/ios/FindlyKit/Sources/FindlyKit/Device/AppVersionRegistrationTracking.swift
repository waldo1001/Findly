import Foundation

/// specs/004-ios-client.md §5 — backs the "every app update" re-registration trigger: remembers,
/// per signed-in user (mirrors `DeviceIdProviding`'s per-user keying — a different user signing in
/// on the same device must be treated as ITS OWN first launch, not skipped because a previous
/// user's version happened to match), which `appVersion` was last successfully registered.
public protocol AppVersionRegistrationTracking {
    func lastRegisteredAppVersion(forUserId userId: String) -> String?
    func setLastRegisteredAppVersion(_ version: String, forUserId userId: String)
    /// specs/008-privacy-endpoints.md §1.3, specs/004-ios-client.md §3.6 (I25) — mirrors
    /// `DeviceIdProviding.clearDeviceId(forUserId:)`. `DeviceRegistrationService.registerOrUpdate()`
    /// (I24) reads a non-nil `lastRegisteredAppVersion` as local evidence "a profile existed for
    /// this user at some point" and skips its pre-flight profile probe on that basis — so this MUST
    /// be cleared whenever an account is fully torn down (`DeleteAccountViewModel`), or a later
    /// sign-in on the same uid could carry a stale "already registered" bit into a session that
    /// genuinely has no profile any more.
    func clearLastRegisteredAppVersion(forUserId userId: String)
}

/// Test/dev default.
public final class InMemoryAppVersionRegistrationTracker: AppVersionRegistrationTracking {
    private var versionsByUser: [String: String] = [:]

    public init() {}

    public func lastRegisteredAppVersion(forUserId userId: String) -> String? { versionsByUser[userId] }
    public func setLastRegisteredAppVersion(_ version: String, forUserId userId: String) { versionsByUser[userId] = version }
    public func clearLastRegisteredAppVersion(forUserId userId: String) { versionsByUser[userId] = nil }
}

/// Persists across launches via `UserDefaults` — the real device implementation.
public final class UserDefaultsAppVersionRegistrationTracker: AppVersionRegistrationTracking {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastRegisteredAppVersion(forUserId userId: String) -> String? { defaults.string(forKey: key(for: userId)) }
    public func setLastRegisteredAppVersion(_ version: String, forUserId userId: String) { defaults.set(version, forKey: key(for: userId)) }
    public func clearLastRegisteredAppVersion(forUserId userId: String) { defaults.removeObject(forKey: key(for: userId)) }

    private func key(for userId: String) -> String { "FindlyKit.lastRegisteredAppVersion.\(userId)" }
}
