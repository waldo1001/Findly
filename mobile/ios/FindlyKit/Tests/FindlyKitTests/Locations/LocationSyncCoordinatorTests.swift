import Foundation
import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §5.1's `batchId` idempotency model end to end + specs/009-device-runtime.md
/// §9's error-handling table — mirrors Android's `LocationSyncCoordinator`/`LocationSyncCoordinatorTest`.
struct LocationSyncCoordinatorTests {

    func makeFix(_ id: String) -> LocationFix {
        LocationFix(fixId: id, recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    func errorEnvelope(_ code: APIErrorCode, details: [String: JSONValue]? = nil) -> APIError {
        .server(APIErrorBody(code: code, message: "boom", details: details, requestId: "req_1"), httpStatus: Self.httpStatus(for: code))
    }

    static func httpStatus(for code: APIErrorCode) -> Int {
        switch code {
        case .trackingPaused: return 403
        case .validationFailed, .locationBatchTooLarge: return 400
        case .deviceNotFound: return 404
        case .authTokenExpired: return 401
        case .internalError: return 500
        default: return 400
        }
    }

    @Test func nothingQueued_returnsNothingToSync_neverCallsTheApi() async {
        let api = FakeAPIClient()
        let queue = FixQueue()
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .nothingToSync)
        #expect(api.reportLocationsCalls.isEmpty)
    }

    // MARK: - Major finding (post-review): client-side pause gate (specs/009 §4)

    @Test func cachedSettingsShowPaused_skipsTheFlushWithoutCallingTheApi_batchStaysQueued() async {
        let api = FakeAPIClient()
        let queue = FixQueue()
        await queue.enqueue(makeFix("f1"))
        let pausedSettings = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }, cachedSettings: { pausedSettings })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .paused(deviceSettings: pausedSettings))
        #expect(api.reportLocationsCalls.isEmpty, "specs/009 §4: a paused device MUST NOT even attempt to flush")
        // The batch must stay queued, untouched, exactly as it was pre-pause - not frozen into
        // an in-flight batch it isn't allowed to send.
        #expect(await queue.queuedCount() == 1)
        let stillPending = await queue.nextBatchToSend()
        #expect(stillPending == nil || stillPending?.fixes.map(\.fixId) == ["f1"], "resuming later must still be able to send it")
    }

    @Test func cachedSettingsShowActive_proceedsNormally() async {
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let coordinator = LocationSyncCoordinator(
            queue: queue, apiClient: api, deviceId: { "device-1" },
            cachedSettings: { DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true) }
        )

        let outcome = await coordinator.syncOnce()

        #expect(outcome != .paused(deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)))
        #expect(api.reportLocationsCalls.count == 1)
    }

    @Test func cachedSettingsUnknown_defaultBehavior_doesNotGateClientSide() async {
        // The default `cachedSettings: { nil }` - every pre-existing call site/test that predates
        // this parameter must keep behaving exactly as before (gating only ever happens when the
        // caller actually wires a real cache).
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        _ = await coordinator.syncOnce()

        #expect(api.reportLocationsCalls.count == 1)
    }

    @Test func noDeviceId_returnsNothingToSync_neverCallsTheApi() async {
        let api = FakeAPIClient()
        let queue = FixQueue()
        await queue.enqueue(makeFix("f1"))
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { nil })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .nothingToSync)
        #expect(api.reportLocationsCalls.isEmpty)
    }

    @Test func success_clearsTheBatch_andReturnsThePiggyback() async {
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(
                accepted: 1, duplicates: 0, lastKnownUpdated: true,
                deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true),
                geofenceEtag: "etag-1"
            ))
        }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .synced(accepted: 1, duplicates: 0, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true), geofenceEtag: "etag-1"))
        #expect(await queue.queuedCount() == 0)
        #expect(api.reportLocationsCalls.first?.batchId == "batch-1")
    }

    @Test func trackingPaused_appliesTheEchoedSettings_leavesTheBatchFrozenForResume() async {
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in
            throw self.errorEnvelope(.trackingPaused, details: [
                "deviceSettings": .object(["syncIntervalMinutes": .number(60), "trackingEnabled": .bool(false)])
            ])
        }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .paused(deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: false)))
        // Fixes recorded before the pause stay queued (001 §5.1: MAY be uploaded after resume).
        #expect(await queue.queuedCount() == 1)
    }

    @Test func validationFailed_dropsOffendingFixes_issuesANewBatchIdForTheRemainder() async {
        let api = FakeAPIClient()
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix("bad-fix"))
        await queue.enqueue(makeFix("good-fix"))
        api.reportLocationsHandler = { _, _, _ in
            throw self.errorEnvelope(.validationFailed, details: ["fields": .array([.string("fixes[0].fixId")])])
        }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .rejected(droppedFixIds: ["bad-fix"]))
        #expect(await queue.queuedCount() == 1)
        let next = await queue.nextBatchToSend()
        #expect(next?.batchId == "batch-2")
        #expect(next?.fixes.map(\.fixId) == ["good-fix"])
    }

    @Test func deviceNotFound_signalsReRegisterDevice() async {
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in throw self.errorEnvelope(.deviceNotFound) }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .reRegisterDevice)
    }

    @Test func authTokenExpiredASecondTime_signalsSignedOut() async {
        // A single AUTH_TOKEN_EXPIRED is already handled by URLSessionAPIClient's retry-once path
        // (specs/001 §2.1) - if it STILL propagates here, the retry already failed once (specs/009 §9).
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in throw self.errorEnvelope(.authTokenExpired) }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .signedOut)
    }

    @Test func networkFailure_keepsTheSameBatchIdForRetry() async {
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in throw APIError.transport("no network") }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .transientFailure)
        let retry = await queue.nextBatchToSend()
        #expect(retry?.batchId == "batch-1")
        #expect(retry?.fixes.map(\.fixId) == ["f1"])
    }

    @Test func serverFiveHundred_isTransient() async {
        let api = FakeAPIClient()
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix("f1"))
        api.reportLocationsHandler = { _, _, _ in throw self.errorEnvelope(.internalError) }
        let coordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .transientFailure)
    }
}
