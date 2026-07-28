import Foundation

/// The cached last-applied `DeviceSettingsSnapshot` (specs/009-device-runtime.md §3.5) — the
/// source of truth `FixCaptureCoordinator`'s `isPaused` closure and `LocationSyncRunner`'s current
/// `syncIntervalMinutes` both read.
public protocol DeviceSettingsStateStoring {
    func current() -> DeviceSettingsSnapshot?
    func update(_ settings: DeviceSettingsSnapshot)
}

/// Test/default in-memory implementation.
public final class InMemoryDeviceSettingsStateStore: DeviceSettingsStateStoring {
    private var settings: DeviceSettingsSnapshot?

    public init(initial: DeviceSettingsSnapshot? = nil) {
        self.settings = initial
    }

    public func current() -> DeviceSettingsSnapshot? { settings }
    public func update(_ settings: DeviceSettingsSnapshot) { self.settings = settings }
}

/// Persists across launches via `UserDefaults` — the real device implementation. specs/009 §1.2's
/// "stop capturing" while paused MUST survive a cold start (a significant-location-change callback
/// can relaunch the app directly into a background launch, §3.4), so this cannot be in-memory-only
/// on a real device.
public final class UserDefaultsDeviceSettingsStateStore: DeviceSettingsStateStoring {
    private let defaults: UserDefaults
    private static let intervalKey = "FindlyKit.deviceSettings.syncIntervalMinutes"
    private static let trackingKey = "FindlyKit.deviceSettings.trackingEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func current() -> DeviceSettingsSnapshot? {
        guard defaults.object(forKey: Self.intervalKey) != nil, defaults.object(forKey: Self.trackingKey) != nil else {
            return nil
        }
        return DeviceSettingsSnapshot(
            syncIntervalMinutes: defaults.integer(forKey: Self.intervalKey),
            trackingEnabled: defaults.bool(forKey: Self.trackingKey)
        )
    }

    public func update(_ settings: DeviceSettingsSnapshot) {
        defaults.set(settings.syncIntervalMinutes, forKey: Self.intervalKey)
        defaults.set(settings.trackingEnabled, forKey: Self.trackingKey)
    }
}
