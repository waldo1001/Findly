import Foundation

/// Seam `LocationSyncRunner`'s two drain loops call through on every accepted `.synced` outcome
/// (specs/001-api-contract.md §5.1/§7.3's `geofenceEtag` piggyback) — kept narrow (rather than a
/// direct `GeofenceConfigSyncCoordinator` reference) so `LocationSyncRunner` doesn't depend on the
/// concrete coordinator type, mirroring `DeviceSettingsApplying`'s seam pattern.
public protocol GeofenceConfigSyncing {
    func syncIfEtagChanged(_ observedEtag: String) async
}

/// Default no-op — `LocationSyncRunner`'s default until a caller wires a real coordinator in
/// (mirrors `NoOpGeofenceRegistrarStub`'s role for `GeofenceRegistrarStub`). Keeps every pre-I11
/// `LocationSyncRunner`/`LocationRuntimeContainer` test call site behaving exactly as before.
public final class NoOpGeofenceConfigSyncing: GeofenceConfigSyncing {
    public init() {}
    public func syncIfEtagChanged(_ observedEtag: String) async {}
}

/// The consolidated "fetch config (`If-None-Match`) -> update cache -> full re-register" sequence
/// (specs/009-device-runtime.md §6.2) that four of the five registration triggers need verbatim:
/// first config sync after sign-in, an observed `geofenceEtag` change ([syncIfEtagChanged] — the
/// piggyback of 001-api-contract.md §5.1/§7.3), resume from pause, and app cold start (both of
/// which lose OS-level geofence registrations per §6.2 without changing anything server-side).
/// Mirrors Android's `GeofenceConfigSyncCoordinator` (`location/settings/GeofenceConfigSyncCoordinator.kt`).
///
/// A `304`/failed fetch still ends in a full re-register from whatever is cached: that's exactly
/// what resume/cold-start need (the OS lost the registrations, not the config), and it's a
/// harmless, if occasionally redundant, no-op for the ETag-mismatch trigger (which only calls
/// [sync] after confirming a real mismatch, so a `304` there would only happen on a race). Nothing
/// cached yet and no fresh body available is a silent best-effort no-op — the same treatment every
/// other specs/009 §1/§5 best-effort path gives a failure.
public final class GeofenceConfigSyncCoordinator: GeofenceConfigSyncing {
    /// specs/000-overview.md §O9: `CLLocationManager` region monitoring is capped at 20 regions
    /// **per app**, a hard platform ceiling independent of whatever `features.limits.maxGeofences`
    /// the server reports. `PLAN_MATRIX` (backend/src/domain/plan.ts) happens to also encode 20
    /// today, but a future paid tier raising the server limit above 20 would need client-side
    /// nearest-region rotation (000 §O9's own noted follow-up) — until that exists, this coordinator
    /// defensively clamps to whichever of the two limits is smaller, so iOS never asks
    /// `CLLocationManager` to monitor more regions than the platform allows.
    public static let platformRegionCap = 20

    private let apiClient: FindlyAPIClient
    private let configStore: GeofenceConfigStateStoring
    private let registrar: GeofenceRegistering

    public init(apiClient: FindlyAPIClient, configStore: GeofenceConfigStateStoring, registrar: GeofenceRegistering) {
        self.apiClient = apiClient
        self.configStore = configStore
        self.registrar = registrar
    }

    /// Unconditional full sync-and-register — every §6.2 trigger except the ETag-mismatch one
    /// (which gates through [syncIfEtagChanged] first) calls this directly.
    public func sync() async {
        let cached = configStore.current()
        do {
            let result = try await apiClient.getGeofences(ifNoneMatch: cached?.etag)
            switch result {
            case .notModified:
                registerFromCache(cached)
            case .ok(let config, let etag, let features):
                let cap = min(features.limits.maxGeofences, Self.platformRegionCap)
                let fresh = CachedGeofenceConfig(etag: etag, geofences: Array(config.geofences.prefix(cap)))
                configStore.update(fresh)
                registrar.registerAll(geofences: fresh.geofences, etag: fresh.etag)
            }
        } catch {
            registerFromCache(cached)
        }
    }

    /// The §6.2 ETag-mismatch trigger (001-api-contract.md §5.1/§7.3's piggyback fires on *every*
    /// flush): only calls [sync] when [observedEtag] actually differs from the cached one, so a
    /// device that hasn't changed its config doesn't re-fetch the whole document on every single
    /// sync cycle.
    public func syncIfEtagChanged(_ observedEtag: String) async {
        if configStore.current()?.etag == observedEtag { return }
        await sync()
    }

    private func registerFromCache(_ cached: CachedGeofenceConfig?) {
        guard let cached else { return }
        registrar.registerAll(geofences: cached.geofences, etag: cached.etag)
    }
}
