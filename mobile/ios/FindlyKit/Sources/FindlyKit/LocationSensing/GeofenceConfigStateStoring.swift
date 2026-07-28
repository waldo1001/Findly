import Foundation

/// The cached geofence config document + its ETag (specs/009-device-runtime.md §6.1: "The client
/// caches the document and its ETag"). Storing the actual `geofences` list — not just the ETag —
/// is what lets `GeofenceConfigSyncCoordinator` re-register from a `304 Not Modified` (config
/// unchanged) or a failed fetch: the resume-from-pause and cold-start triggers (§6.2) need the
/// platform registrations rebuilt even when nothing changed server-side, since it's the OS-level
/// registration that was lost, not the config. Mirrors Android's `CachedGeofenceConfig`
/// (`location/settings/GeofenceConfigStateStore.kt`).
public struct CachedGeofenceConfig: Equatable {
    public let etag: String
    public let geofences: [Geofence]

    public init(etag: String, geofences: [Geofence]) {
        self.etag = etag
        self.geofences = geofences
    }
}

/// Persists `CachedGeofenceConfig` across process restarts (specs/009-device-runtime.md §6.1) —
/// the same interface + real/fake split as `DeviceSettingsStateStoring`
/// (`UserDefaultsGeofenceConfigStateStore` is the real implementation).
public protocol GeofenceConfigStateStoring {
    func current() -> CachedGeofenceConfig?
    func update(_ config: CachedGeofenceConfig)

    /// Drops the cached document/ETag unconditionally — used only by a full local-state wipe after
    /// account deletion (specs/008-privacy-endpoints.md §4.4; specs/004-ios-client.md §3.6: "clear
    /// all local state"), same as `FixQueue.clearAll()`/`GeofenceEventQueue.clearAll()`.
    func clear()
}

/// Test/default in-memory implementation.
public final class InMemoryGeofenceConfigStateStore: GeofenceConfigStateStoring {
    private var config: CachedGeofenceConfig?

    public init(initial: CachedGeofenceConfig? = nil) {
        self.config = initial
    }

    public func current() -> CachedGeofenceConfig? { config }
    public func update(_ config: CachedGeofenceConfig) { self.config = config }
    public func clear() { config = nil }
}

/// Persists across launches via `UserDefaults` — the real device implementation. The geofence list
/// is JSON-encoded (via `Geofence`'s existing `Codable` conformance, specs/001 §7.1's wire shape)
/// into a single `UserDefaults` string value, mirroring `UserDefaultsDeviceSettingsStateStore`'s
/// two-key shape and Android's `SharedPreferencesGeofenceConfigStateStore`'s "not sensitive — a
/// family already configured these names/coordinates, not a credential" posture.
public final class UserDefaultsGeofenceConfigStateStore: GeofenceConfigStateStoring {
    private let defaults: UserDefaults
    private static let etagKey = "FindlyKit.geofenceConfig.etag"
    private static let geofencesKey = "FindlyKit.geofenceConfig.geofencesJson"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func current() -> CachedGeofenceConfig? {
        guard let etag = defaults.string(forKey: Self.etagKey),
              let json = defaults.data(forKey: Self.geofencesKey),
              let geofences = try? JSONDecoder().decode([Geofence].self, from: json) else {
            return nil
        }
        return CachedGeofenceConfig(etag: etag, geofences: geofences)
    }

    public func update(_ config: CachedGeofenceConfig) {
        guard let json = try? JSONEncoder().encode(config.geofences) else { return }
        defaults.set(config.etag, forKey: Self.etagKey)
        defaults.set(json, forKey: Self.geofencesKey)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.etagKey)
        defaults.removeObject(forKey: Self.geofencesKey)
    }
}
