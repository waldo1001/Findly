import Foundation

/// specs/010 §1.4 — the app-lock setting and the time the app was last backgrounded. Local per
/// install, never sent to the server; both are cleared by the end-of-session wipe
/// (`EndOfSessionRoutine`).
public protocol AppLockSettingsStoring: AnyObject {
    var isEnabled: Bool { get set }
    var backgroundedAt: Date? { get set }
    func clear()
}

public final class InMemoryAppLockSettingsStore: AppLockSettingsStoring {
    public var isEnabled = false
    public var backgroundedAt: Date?
    public init() {}
    public func clear() {
        isEnabled = false
        backgroundedAt = nil
    }
}

/// App-private `UserDefaults`: the flag gates the UI, it is not a secret, and the lock is an app
/// gate rather than a cryptographic one (010 §1.4).
public final class UserDefaultsAppLockSettingsStore: AppLockSettingsStoring {
    static let enabledKey = "com.findly.appLock.enabled"
    static let backgroundedAtKey = "com.findly.appLock.backgroundedAt"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    public var backgroundedAt: Date? {
        get { defaults.object(forKey: Self.backgroundedAtKey) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.backgroundedAtKey)
            } else {
                defaults.removeObject(forKey: Self.backgroundedAtKey)
            }
        }
    }

    public func clear() {
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.backgroundedAtKey)
    }
}
