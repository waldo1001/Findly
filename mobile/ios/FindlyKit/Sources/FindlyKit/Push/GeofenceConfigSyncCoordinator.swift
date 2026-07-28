import Foundation

/// specs/001-api-contract.md §7.1, specs/009-device-runtime.md §6.1/§6.2 — the consolidated
/// fetch-cache-register sequence: `GET /geofences` with the cached `If-None-Match` ETag, and on a
/// `200`, cache the new ETag and hand the config off to `GeofenceConfigRegistering` (I11's seam,
/// or its documented no-op placeholder until I11 lands). A `304`/API failure is a silent no-op —
/// nothing changed, or nothing usable came back; never crashes the caller. Mirrors Android's
/// `GeofenceConfigSyncCoordinator`.
public final class GeofenceConfigSyncCoordinator {
    private let apiClient: FindlyAPIClient
    private let cache: GeofenceConfigCaching
    private let registrar: GeofenceConfigRegistering

    public init(apiClient: FindlyAPIClient, cache: GeofenceConfigCaching, registrar: GeofenceConfigRegistering) {
        self.apiClient = apiClient
        self.cache = cache
        self.registrar = registrar
    }

    public func sync() async {
        guard let result = try? await apiClient.getGeofences(ifNoneMatch: cache.cachedEtag()) else { return }
        switch result {
        case .notModified:
            return
        case .ok(let config, let etag):
            cache.cache(etag: etag)
            await registrar.registerAll(config.geofences)
        }
    }
}
