import Foundation

/// `GEOFENCE_CONFIG_CHANGED` (specs/001-api-contract.md §8.4; specs/009-device-runtime.md §5.4): a
/// thin delegate onto `GeofenceConfigSyncCoordinator.sync()` — the payload's own `etag` field is
/// informational only (the coordinator's cached ETag, sent as `If-None-Match`, is the actual source
/// of truth), so the handler ignores `data` entirely, exactly like Android's
/// `GeofenceConfigChangedPushHandler`.
public final class GeofenceConfigChangedPushHandler: GeofenceConfigChangedHandling {
    private let syncCoordinator: GeofenceConfigSyncCoordinator

    public init(syncCoordinator: GeofenceConfigSyncCoordinator) {
        self.syncCoordinator = syncCoordinator
    }

    public func handle(_ data: [String: String]) async {
        await syncCoordinator.sync()
    }
}
