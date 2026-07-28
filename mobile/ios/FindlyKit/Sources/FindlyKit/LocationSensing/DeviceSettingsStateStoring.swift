import Foundation

/// The cached last-applied `DeviceSettingsSnapshot` (specs/009-device-runtime.md §3.5) — the
/// source of truth `FixCaptureCoordinator`'s `isPaused` closure and `LocationSyncRunner`'s current
/// `syncIntervalMinutes` both read.
public protocol DeviceSettingsStateStoring {
    func current() -> DeviceSettingsSnapshot?
    func update(_ settings: DeviceSettingsSnapshot)

    /// Resets to a **definite "no active session, do not capture" state** — part of
    /// `LocationRuntimeContainer.wipeLocalState()`'s sign-out/account-deletion wipe (specs/008 §4.4,
    /// specs/009 §4). Deliberately **not** a bare "forget everything" the way
    /// `GeofenceConfigStateStoring.clear()`/`FixQueue.clearAll()` are: a genuinely fresh install's
    /// `current() == nil` is treated as *safe-to-try* by several existing call sites
    /// (`LocationRuntimeContainer.start()`'s cold-start bootstrap, and `FixCaptureCoordinator`/
    /// `GeofenceTransitionHandler`'s own `current()?.trackingEnabled == false` pause gates — nil
    /// reads as "assume active until proven otherwise" everywhere in this codebase, matching
    /// specs/009's "no fix is better than silently doing nothing forever" first-launch reasoning).
    /// A just-signed-out device is a different, DEFINITE state, not an unknown one — conflating the
    /// two by nil-ing the value out would leave every pause gate reading "not paused" again
    /// (nil evaluates the same as "unknown" there), silently resuming capture/geofence-transition
    /// queuing under whatever *new* session/deviceId comes next. Implementations MUST therefore
    /// write an explicit `trackingEnabled: false` snapshot, never simply clear the stored value.
    func clear()
}

/// Test/default in-memory implementation.
public final class InMemoryDeviceSettingsStateStore: DeviceSettingsStateStoring {
    private var settings: DeviceSettingsSnapshot?

    public init(initial: DeviceSettingsSnapshot? = nil) {
        self.settings = initial
    }

    public func current() -> DeviceSettingsSnapshot? { settings }
    public func update(_ settings: DeviceSettingsSnapshot) { self.settings = settings }

    public func clear() {
        settings = DeviceSettingsSnapshot(syncIntervalMinutes: settings?.syncIntervalMinutes ?? 15, trackingEnabled: false)
    }
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

    public func clear() {
        let interval = current()?.syncIntervalMinutes ?? 15
        update(DeviceSettingsSnapshot(syncIntervalMinutes: interval, trackingEnabled: false))
    }
}
