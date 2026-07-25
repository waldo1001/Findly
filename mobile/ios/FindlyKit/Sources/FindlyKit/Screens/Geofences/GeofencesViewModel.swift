import Foundation

/// specs/004-ios-client.md I2 (001 §7.1–7.2) — the geofences list/editor's ETag-aware sync. `load()`
/// caches the response `ETag`; `save(_:)` sends it back as `If-Match`. On `409
/// GEOFENCE_VERSION_CONFLICT` the view model re-fetches the true current server copy and surfaces
/// it via `conflict` for the caller's merge UX, rather than silently overwriting or discarding the
/// user's edits.
@MainActor
public final class GeofencesViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(geofences: [Geofence], version: Int)
        case error(String)
    }

    public enum ConflictState: Equatable {
        case none
        case versionConflict(serverGeofences: [Geofence], serverVersion: Int)
    }

    @Published public private(set) var state: State = .loading
    @Published public private(set) var conflict: ConflictState = .none
    @Published public private(set) var isSaving = false

    private let apiClient: FindlyAPIClient
    private var cachedETag: String?

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        // Only blank out to `.loading` on the very first load. A subsequent refresh keeps
        // showing the last-known list while it's in flight — and a `304` (unchanged) must leave
        // that state untouched rather than getting stuck on `.loading` forever (§7.1).
        if cachedETag == nil {
            state = .loading
        }
        do {
            let result = try await apiClient.getGeofences(ifNoneMatch: cachedETag)
            apply(result)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    private func apply(_ result: GeofencesResult) {
        switch result {
        case .notModified:
            break
        case .ok(let config, let etag):
            cachedETag = etag
            state = .loaded(geofences: config.geofences, version: config.version)
        }
    }

    /// specs/001 §7.2 — full-document replace, `If-Match` required (the `"0"` sentinel for a
    /// family's first-ever write is just whatever `load()` cached). Requires a prior successful
    /// `load()`; this is enforced rather than assumed, so a caller that skips `load()` gets a clear
    /// error instead of an accidental `If-Match`-less request.
    public func save(_ geofences: [Geofence]) async {
        guard let etag = cachedETag else {
            state = .error("Load the current geofences before saving.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let (config, newETag) = try await apiClient.replaceGeofences(geofences, ifMatch: etag)
            cachedETag = newETag
            state = .loaded(geofences: config.data.geofences, version: config.data.version)
            conflict = .none
        } catch {
            if (error as? APIError)?.serverCode == .geofenceVersionConflict {
                await refetchAfterConflict()
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    private func refetchAfterConflict() async {
        do {
            // Force a fresh copy regardless of any cached ETag so the conflict UX always compares
            // against the true current server state.
            let result = try await apiClient.getGeofences(ifNoneMatch: nil)
            if case .ok(let config, let etag) = result {
                cachedETag = etag
                conflict = .versionConflict(serverGeofences: config.geofences, serverVersion: config.version)
            }
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    /// The merge UX's "discard my edits, adopt the server's copy" affordance.
    public func acceptServerVersion() {
        guard case .versionConflict(let serverGeofences, let serverVersion) = conflict else { return }
        state = .loaded(geofences: serverGeofences, version: serverVersion)
        conflict = .none
    }

    public func dismissConflict() {
        conflict = .none
    }
}
