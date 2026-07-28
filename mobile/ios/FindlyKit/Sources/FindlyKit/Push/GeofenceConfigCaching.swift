import Foundation

/// specs/009-device-runtime.md §6.1 — "the client caches the document and its ETag." Backs the
/// `If-None-Match` conditional `GET /geofences` call every §6.2 trigger (incl. the
/// `GEOFENCE_CONFIG_CHANGED` push) makes through `GeofenceConfigSyncCoordinator`.
public protocol GeofenceConfigCaching {
    func cachedEtag() -> String?
    func cache(etag: String)
}

/// Test/dev default.
public final class InMemoryGeofenceConfigCache: GeofenceConfigCaching {
    private var etag: String?

    public init(etag: String? = nil) {
        self.etag = etag
    }

    public func cachedEtag() -> String? { etag }
    public func cache(etag: String) { self.etag = etag }
}

/// Persists across launches via `UserDefaults` — the real device implementation.
public final class UserDefaultsGeofenceConfigCache: GeofenceConfigCaching {
    private let defaults: UserDefaults
    private static let etagKey = "FindlyKit.geofenceConfig.etag"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func cachedEtag() -> String? { defaults.string(forKey: Self.etagKey) }
    public func cache(etag: String) { defaults.set(etag, forKey: Self.etagKey) }
}
