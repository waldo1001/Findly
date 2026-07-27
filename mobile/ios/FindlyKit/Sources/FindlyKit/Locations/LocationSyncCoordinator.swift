import Foundation

/// The outcome of a single `LocationSyncCoordinator.syncOnce` call (specs/009-device-runtime.md
/// §9's error-handling table). Mirrors Android's `SyncOutcome`.
public enum SyncOutcome: Equatable {
    case nothingToSync

    /// 001-api-contract.md §5.1: **every** accepted response carries the current `deviceSettings`
    /// + `geofenceEtag` piggyback — applying `deviceSettings` is mandatory on every `.synced`
    /// outcome (specs/009 §1), not just a `.paused` nicety. `geofenceEtag` is threaded through
    /// (not consumed yet — I11's §6.2 ETag-mismatch re-sync) so it's available to whoever wires
    /// that next, rather than dropped on the floor.
    case synced(accepted: Int, duplicates: Int, deviceSettings: DeviceSettingsSnapshot, geofenceEtag: String)

    /// Network error / 5xx — the in-flight batch is untouched (same `batchId`, identical content
    /// on the next `nextBatchToSend`, specs/001 §5.1).
    case transientFailure

    /// A definitive 4xx (`VALIDATION_FAILED`/`LOCATION_BATCH_TOO_LARGE`) — the offending fixes are
    /// already dropped and the remainder already un-frozen by the time this is returned.
    case rejected(droppedFixIds: Set<String>)

    /// `403 TRACKING_PAUSED`, with `error.details.deviceSettings` decoded (specs/009 §9). The
    /// batch stays frozen, untouched, ready to resend after resume.
    case paused(deviceSettings: DeviceSettingsSnapshot)

    /// `404 DEVICE_NOT_FOUND` on a device-originated call (specs/009 §9) — this registration is
    /// gone; the caller must stop the schedule, clear local device state, and re-run registration.
    case reRegisterDevice

    /// A second consecutive `401 AUTH_TOKEN_EXPIRED` — the first is already handled by
    /// `URLSessionAPIClient`'s retry-once path (specs/001 §2.1); a second failure means signed-out
    /// (specs/009 §9).
    case signedOut

    /// Any other non-definitive failure (unexpected 4xx, transport/decoding trouble not otherwise
    /// classified) — treated as retryable, matching Android's `OtherFailure` catch-all.
    case otherFailure
}

/// Ties `FixQueue` + `FindlyAPIClient` together, implementing 001-api-contract.md §5.1's `batchId`
/// idempotency model end to end (specs/004-ios-client.md §6) — the real sync/upload runner's
/// network-touching half. Fully unit-testable: no CoreLocation/BackgroundTasks involved, only
/// `FixQueue` (backed by any `FixStoring`) and `FindlyAPIClient` (fakeable). Mirrors Android's
/// `LocationSyncCoordinator`.
public final class LocationSyncCoordinator {
    private let queue: FixQueue
    private let apiClient: FindlyAPIClient
    /// Resolved per-call (not captured once) so a caller that just signed in / just finished
    /// device registration sees the fresh id on the very next `syncOnce`, with no separate wiring.
    /// `nil` means "no deviceId to sync under" (not yet registered / signed out) - `.nothingToSync`
    /// rather than attempting (and failing) a call the server would reject anyway.
    private let deviceId: () -> String?
    private let maxBatchSize: Int

    public init(queue: FixQueue, apiClient: FindlyAPIClient, deviceId: @escaping () -> String?, maxBatchSize: Int = 100) {
        self.queue = queue
        self.apiClient = apiClient
        self.deviceId = deviceId
        self.maxBatchSize = maxBatchSize
    }

    public func syncOnce() async -> SyncOutcome {
        guard let deviceId = deviceId() else { return .nothingToSync }
        guard let batch = await queue.nextBatchToSend(maxBatchSize: maxBatchSize) else { return .nothingToSync }

        do {
            let envelope = try await apiClient.reportLocations(deviceId: deviceId, batchId: batch.batchId, fixes: batch.fixes)
            await queue.handleAccepted(batchId: batch.batchId)
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

    private func handleFailure(batch: PendingBatch, error: APIError) async -> SyncOutcome {
        guard case .server(let body, let httpStatus) = error else {
            // .transport / .decoding / .notModified (the last never actually reachable from
            // reportLocations, which never passes notModifiedIsSuccess) - all treated as
            // transient/retryable, same as a network failure.
            await queue.handleTransientFailure(batchId: batch.batchId)
            return .transientFailure
        }

        switch body.code {
        case .trackingPaused:
            guard let settings = Self.deviceSettings(from: body.details) else { return .otherFailure }
            // Deliberately does NOT resolve the batch either way - a paused device must not
            // flush, but the frozen fixes stay exactly as they are, ready to resend once resumed
            // (specs/001 §5.1: "fixes recorded before the pause MAY still be uploaded after resume").
            return .paused(deviceSettings: settings)

        case .validationFailed:
            let dropped = Self.offendingFixIds(batch: batch, fields: body.details?["fields"])
            await queue.handleDefinitiveRejection(batchId: batch.batchId, dropFixIds: dropped)
            return .rejected(droppedFixIds: dropped)

        case .locationBatchTooLarge:
            // Defensive-only: our own nextBatchToSend(maxBatchSize:) never actually produces
            // >100-fix batches. Un-freeze the whole batch so a fresh batchId gets assigned next
            // time, dropping nothing specific.
            await queue.handleDefinitiveRejection(batchId: batch.batchId, dropFixIds: [])
            return .rejected(droppedFixIds: [])

        case .deviceNotFound:
            return .reRegisterDevice

        case .authTokenExpired:
            return .signedOut

        default:
            if (500...599).contains(httpStatus) {
                await queue.handleTransientFailure(batchId: batch.batchId)
                return .transientFailure
            }
            // Any other 4xx (e.g. AUTH_FORBIDDEN, RATE_LIMITED) is not one of §5.1's documented
            // "definitive rejection" shapes - treat as transient/retryable rather than silently
            // dropping fixes, matching Android's OtherFailure handling.
            await queue.handleTransientFailure(batchId: batch.batchId)
            return .otherFailure
        }
    }

    /// specs/009 §9: "403 TRACKING_PAUSED... using the error.details.deviceSettings echoed in the
    /// response." `details` is untyped JSON (`[String: JSONValue]?`, specs/001 §1.3) since its
    /// shape varies per error code.
    private static func deviceSettings(from details: [String: JSONValue]?) -> DeviceSettingsSnapshot? {
        guard case .object(let settingsObject)? = details?["deviceSettings"] else { return nil }
        guard case .number(let interval)? = settingsObject["syncIntervalMinutes"],
              case .bool(let tracking)? = settingsObject["trackingEnabled"] else { return nil }
        return DeviceSettingsSnapshot(syncIntervalMinutes: Int(interval), trackingEnabled: tracking)
    }

    /// `details.fields` (specs/001 §10) names offending fields as `"fixes[N].<field>"` — maps each
    /// back to the batch's Nth fix id. Mirrors Android's `offendingFixIdsFrom` exactly: an
    /// absent/empty/unmappable `fields` array yields an **empty** drop set, not "drop everything"
    /// — `FixQueue.handleDefinitiveRejection` is always called with a concrete (possibly empty)
    /// `Set` here, never `nil`, so an unmappable rejection un-freezes the whole batch (nothing
    /// dropped) rather than destroying fixes the server never actually named as bad.
    private static func offendingFixIds(batch: PendingBatch, fields: JSONValue?) -> Set<String> {
        guard case .array(let values)? = fields else { return [] }
        let paths = values.compactMap { value -> String? in
            if case .string(let path) = value { return path }
            return nil
        }
        var result: Set<String> = []
        for path in paths {
            guard let index = Self.fixesIndex(from: path), batch.fixes.indices.contains(index) else { continue }
            result.insert(batch.fixes[index].fixId)
        }
        return result
    }

    private static func fixesIndex(from fieldPath: String) -> Int? {
        guard let openBracket = fieldPath.firstIndex(of: "["), let closeBracket = fieldPath.firstIndex(of: "]"),
              fieldPath.hasPrefix("fixes["), openBracket < closeBracket else { return nil }
        return Int(fieldPath[fieldPath.index(after: openBracket)..<closeBracket])
    }
}
