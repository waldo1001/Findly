import Foundation

/// The outcome of a single `GeofenceEventSyncCoordinator.syncOnce` call — deliberately mirrors
/// `SyncOutcome`'s shape (same downstream reaction mapping in `LocationSyncRunner`). No
/// `.rejected(droppedFixIds:)` analog: 001-api-contract.md §7.3 defines no per-event rejection
/// shape, unlike §5.1's `details.fields`.
public enum GeofenceEventSyncOutcome: Equatable {
    case nothingToSync

    /// 001-api-contract.md §7.3: "same piggyback fields as §5.1" — callers MUST apply
    /// `deviceSettings` and compare `geofenceEtag` against the cached one (specs/009 §6.3: "the
    /// device SHOULD notice the geofenceEtag mismatch... and re-sync config").
    case synced(accepted: Int, duplicates: Int, deviceSettings: DeviceSettingsSnapshot, geofenceEtag: String)

    /// Network error / 5xx — the in-flight batch is untouched (same `batchId`, identical content
    /// on the next `nextBatchToSend`).
    case transientFailure

    /// `403 TRACKING_PAUSED`, with `error.details.deviceSettings` decoded. The batch stays frozen,
    /// untouched, ready to resend after resume.
    case paused(deviceSettings: DeviceSettingsSnapshot)

    /// `404 DEVICE_NOT_FOUND` on a device-originated call (specs/009 §9).
    case reRegisterDevice

    /// A second consecutive `401 AUTH_TOKEN_EXPIRED` (specs/009 §9).
    case signedOut

    /// Any other non-definitive failure — no per-event rejection shape is defined for this
    /// endpoint (unlike §5.1's `details.fields`), so this is treated as retryable, same as
    /// `LocationSyncCoordinator`'s own catch-all.
    case otherFailure
}

/// Seam `LocationSyncRunner` drains through on every trigger — kept narrow (rather than a direct
/// `GeofenceEventSyncCoordinator` reference) so `LocationSyncRunner` doesn't depend on the concrete
/// coordinator type, mirroring `DeviceSettingsApplying`/`GeofenceConfigSyncing`'s seam pattern.
public protocol GeofenceEventDraining {
    func syncOnce() async -> GeofenceEventSyncOutcome
}

/// Default no-op — `LocationSyncRunner`'s default until a caller wires a real coordinator in.
/// Keeps every pre-I11 `LocationSyncRunner` test call site behaving exactly as before.
public final class NoOpGeofenceEventDraining: GeofenceEventDraining {
    public init() {}
    public func syncOnce() async -> GeofenceEventSyncOutcome { .nothingToSync }
}

/// Ties `GeofenceEventQueue` + `FindlyAPIClient.reportGeofenceEvents` together (001-api-contract.md
/// §7.3), mirroring `LocationSyncCoordinator`'s role for the fix queue. Unlike location batches,
/// §7.3 defines no per-event rejection shape — every failure other than `TRACKING_PAUSED` keeps
/// the batch frozen for an identical retry, the same "retry rather than silently drop" posture
/// `LocationSyncCoordinator.handleFailure`'s own `default` branch takes for any undocumented
/// failure shape. Mirrors Android's `GeofenceEventSyncCoordinator`.
public final class GeofenceEventSyncCoordinator: GeofenceEventDraining {
    private let queue: GeofenceEventQueue
    private let apiClient: FindlyAPIClient
    private let deviceId: () -> String?
    /// specs/009 §4: the same client-side pause gate `LocationSyncCoordinator.cachedSettings`
    /// established — reads the locally cached settings so a paused device doesn't even freeze a
    /// batch it isn't allowed to send. Defaults to `{ nil }` ("unknown, don't gate client-side").
    private let cachedSettings: () -> DeviceSettingsSnapshot?
    private let maxBatchSize: Int

    public init(
        queue: GeofenceEventQueue,
        apiClient: FindlyAPIClient,
        deviceId: @escaping () -> String?,
        cachedSettings: @escaping () -> DeviceSettingsSnapshot? = { nil },
        maxBatchSize: Int = 20
    ) {
        self.queue = queue
        self.apiClient = apiClient
        self.deviceId = deviceId
        self.cachedSettings = cachedSettings
        self.maxBatchSize = maxBatchSize
    }

    public func syncOnce() async -> GeofenceEventSyncOutcome {
        guard let deviceId = deviceId() else { return .nothingToSync }
        if let settings = cachedSettings(), settings.trackingEnabled == false {
            return .paused(deviceSettings: settings)
        }
        guard let batch = await queue.nextBatchToSend(maxBatchSize: maxBatchSize) else { return .nothingToSync }

        do {
            let envelope = try await apiClient.reportGeofenceEvents(deviceId: deviceId, events: batch.events)
            await queue.handleSent(batchId: batch.batchId)
            return .synced(
                accepted: envelope.data.accepted,
                duplicates: envelope.data.duplicates,
                deviceSettings: envelope.data.deviceSettings,
                geofenceEtag: envelope.data.geofenceEtag
            )
        } catch let error as APIError {
            return await handleFailure(batch: batch, error: error)
        } catch {
            await queue.handleTransientFailure(batchId: batch.batchId)
            return .transientFailure
        }
    }

    private func handleFailure(batch: GeofenceEventBatch, error: APIError) async -> GeofenceEventSyncOutcome {
        guard case .server(let body, let httpStatus) = error else {
            await queue.handleTransientFailure(batchId: batch.batchId)
            return .transientFailure
        }

        switch body.code {
        case .trackingPaused:
            guard let settings = LocationSyncCoordinator.deviceSettings(from: body.details) else { return .otherFailure }
            return .paused(deviceSettings: settings)

        case .deviceNotFound:
            return .reRegisterDevice

        case .authTokenExpired:
            return .signedOut

        default:
            // No per-event rejection shape is defined for this endpoint (001 §7.3) - keep
            // retrying rather than silently dropping detected transitions (specs/009 §6.3 treats a
            // lost transition as a MUST-not, unlike a dropped mid-GPS-capture fix).
            await queue.handleTransientFailure(batchId: batch.batchId)
            if (500...599).contains(httpStatus) { return .transientFailure }
            return .otherFailure
        }
    }
}
