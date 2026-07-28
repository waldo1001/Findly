import Foundation
import Testing
@testable import FindlyKit

/// 001-api-contract.md §7.3's batch/idempotency model + specs/009-device-runtime.md §9's
/// error-handling table, applied to the geofence-event queue. Mirrors
/// `LocationSyncCoordinatorTests`/Android's `GeofenceEventSyncCoordinatorTest`.
struct GeofenceEventSyncCoordinatorTests {

    func makeEvent(_ id: String) -> GeofenceEventReport {
        GeofenceEventReport(eventId: id, geofenceId: "gf_home", transition: .enter, recordedAt: "2026-07-19T09:00:00Z")
    }

    func errorEnvelope(_ code: APIErrorCode, details: [String: JSONValue]? = nil, httpStatus: Int) -> APIError {
        .server(APIErrorBody(code: code, message: "boom", details: details, requestId: "req_1"), httpStatus: httpStatus)
    }

    @Test func nothingQueued_returnsNothingToSync_neverCallsTheApi() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue()
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .nothingToSync)
        #expect(api.reportGeofenceEventsCalls.isEmpty)
    }

    @Test func noDeviceId_returnsNothingToSync_neverCallsTheApi() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue()
        await queue.enqueue(makeEvent("e1"))
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { nil })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .nothingToSync)
        #expect(api.reportGeofenceEventsCalls.isEmpty)
    }

    @Test func cachedSettingsShowPaused_skipsTheFlushWithoutCallingTheApi_batchStaysQueued() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue()
        await queue.enqueue(makeEvent("e1"))
        let pausedSettings = DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false)
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }, cachedSettings: { pausedSettings })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .paused(deviceSettings: pausedSettings))
        #expect(api.reportGeofenceEventsCalls.isEmpty, "specs/009 §4: a paused device MUST NOT even attempt to flush")
        #expect(await queue.pendingCount() == 1)
    }

    @Test func success_clearsTheBatch_andReturnsThePiggyback() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in
            TestFeatures.envelope(ReportGeofenceEventsResponse(
                accepted: 1, duplicates: 0,
                deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true),
                geofenceEtag: "etag-1"
            ))
        }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .synced(accepted: 1, duplicates: 0, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true), geofenceEtag: "etag-1"))
        #expect(await queue.pendingCount() == 0)
        #expect(api.reportGeofenceEventsCalls.first?.deviceId == "device-1")
        #expect(api.reportGeofenceEventsCalls.first?.events.map(\.eventId) == ["e1"])
    }

    @Test func trackingPaused_appliesTheEchoedSettings_leavesTheBatchFrozenForResume() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in
            throw self.errorEnvelope(.trackingPaused, details: [
                "deviceSettings": .object(["syncIntervalMinutes": .number(60), "trackingEnabled": .bool(false)])
            ], httpStatus: 403)
        }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .paused(deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: false)))
        #expect(await queue.pendingCount() == 1)
    }

    @Test func deviceNotFound_signalsReRegisterDevice() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in throw self.errorEnvelope(.deviceNotFound, httpStatus: 404) }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .reRegisterDevice)
    }

    @Test func authTokenExpiredASecondTime_signalsSignedOut() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in throw self.errorEnvelope(.authTokenExpired, httpStatus: 401) }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .signedOut)
    }

    @Test func networkFailure_keepsTheSameBatchIdForRetry() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in throw APIError.transport("no network") }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .transientFailure)
        let retry = await queue.nextBatchToSend()
        #expect(retry?.batchId == "batch-1")
        #expect(retry?.events.map(\.eventId) == ["e1"])
    }

    @Test func serverFiveHundred_isTransient_andRetriesTheSameBatch() async {
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in throw self.errorEnvelope(.internalError, httpStatus: 500) }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .transientFailure)
        let retry = await queue.nextBatchToSend()
        #expect(retry?.batchId == "batch-1", "no per-event rejection shape exists (001 §7.3) - the whole batch retries")
    }

    @Test func unmappedFourHundredError_isOtherFailure_andAlsoRetriesTheSameBatch() async {
        // Unlike LocationSyncCoordinator's validationFailed/locationBatchTooLarge branches, §7.3
        // defines NO per-event rejection shape at all - every non-paused, non-5xx failure still
        // keeps the batch frozen for retry, it just isn't classified as .transientFailure.
        let api = FakeAPIClient()
        let queue = GeofenceEventQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeEvent("e1"))
        api.reportGeofenceEventsHandler = { _, _ in throw self.errorEnvelope(.rateLimited, httpStatus: 429) }
        let coordinator = GeofenceEventSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })

        let outcome = await coordinator.syncOnce()

        #expect(outcome == .otherFailure)
        let retry = await queue.nextBatchToSend()
        #expect(retry?.batchId == "batch-1")
        #expect(retry?.events.map(\.eventId) == ["e1"])
    }

    @Test func noOpGeofenceEventDraining_isASafeDefault() async {
        let noOp = NoOpGeofenceEventDraining()
        #expect(await noOp.syncOnce() == .nothingToSync)
    }
}
