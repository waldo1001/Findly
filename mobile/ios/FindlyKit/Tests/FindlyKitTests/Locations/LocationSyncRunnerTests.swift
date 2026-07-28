import Foundation
import Testing
@testable import FindlyKit

private final class FakeDeviceSettingsApplying: DeviceSettingsApplying {
    private(set) var appliedSettings: [DeviceSettingsSnapshot] = []
    func applySettings(_ settings: DeviceSettingsSnapshot) async { appliedSettings.append(settings) }
}

/// I11 addition — records every `syncIfEtagChanged` call so tests can assert `LocationSyncRunner`
/// actually threads the piggybacked `geofenceEtag` through (specs/009 §6.2/§6.3), without needing
/// a real `GeofenceConfigSyncCoordinator`/`FakeAPIClient.getGeofencesHandler` round trip - that
/// sequence has its own dedicated coverage in `GeofenceConfigSyncCoordinatorTests`.
private final class FakeGeofenceConfigSyncing: GeofenceConfigSyncing {
    private(set) var syncIfEtagChangedCalls: [String] = []
    func syncIfEtagChanged(_ observedEtag: String) async { syncIfEtagChangedCalls.append(observedEtag) }
}

/// I11 addition — a scriptable `GeofenceEventDraining` so `LocationSyncRunner`'s own
/// orchestration of the geofence-event drain loop (§6.3) can be tested without a real
/// `GeofenceEventSyncCoordinator`/queue/API round trip (that has its own dedicated coverage in
/// `GeofenceEventSyncCoordinatorTests`).
private final class FakeGeofenceEventDraining: GeofenceEventDraining {
    var outcomes: [GeofenceEventSyncOutcome] = [.nothingToSync]
    private(set) var syncOnceCallCount = 0
    func syncOnce() async -> GeofenceEventSyncOutcome {
        defer { syncOnceCallCount += 1 }
        return outcomes[min(syncOnceCallCount, outcomes.count - 1)]
    }
}

/// specs/009-device-runtime.md §1/§3.4/§9 — the per-trigger orchestration: maybe-capture-a-periodic-
/// fix (gated by `SyncTriggerPolicy`'s 0.8 rule) then drain the queue, applying the mandatory
/// settings piggyback and reacting to `SyncOutcome` per §9's table. Mirrors Android's
/// `LocationSyncRunner`, scoped to what I10 owns (no geofence-event queue - that's I11).
struct LocationSyncRunnerTests {

    func makeFix() -> LocationFix {
        LocationFix(fixId: UUID().uuidString, recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    @Test func belowTheEightyPercentThreshold_doesNotCapture_butStillDrainsAnyQueuedFixes() async {
        let provider = FakeLocationProviding()
        let api = FakeAPIClient()
        let store = InMemoryFixStore()
        let queue = FixQueue(store: store)
        await queue.enqueue(makeFix()) // already-queued fix from an earlier trigger
        let lastQueuedFixAtStore = InMemoryLastQueuedFixAtStore(initial: Date())
        let syncCoordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })
        let captureCoordinator = FixCaptureCoordinator(provider: provider, queue: queue, isPaused: { false }, isPermissionGranted: { true })
        let settingsApplying = FakeDeviceSettingsApplying()
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: lastQueuedFixAtStore, now: { Date() },
            captureCoordinator: captureCoordinator, syncCoordinator: syncCoordinator, settingsApplying: settingsApplying,
            onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(provider.requestSingleFixCalls.isEmpty, "under the 0.8 threshold - no new capture")
        #expect(api.reportLocationsCalls.count == 1, "the already-queued fix must still be drained")
    }

    @Test func aboveTheEightyPercentThreshold_capturesThenDrains() async {
        let provider = FakeLocationProviding()
        provider.nextFix = .success(makeFix())
        let api = FakeAPIClient()
        let queue = FixQueue()
        let lastQueuedFixAtStore = InMemoryLastQueuedFixAtStore(initial: Date(timeIntervalSince1970: 0))
        let syncCoordinator = LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" })
        let captureCoordinator = FixCaptureCoordinator(provider: provider, queue: queue, isPaused: { false }, isPermissionGranted: { true })
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: lastQueuedFixAtStore, now: { Date() },
            captureCoordinator: captureCoordinator, syncCoordinator: syncCoordinator, settingsApplying: FakeDeviceSettingsApplying(),
            onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(provider.requestSingleFixCalls == [.periodic])
        #expect(api.reportLocationsCalls.count == 1)
    }

    @Test func successfulSync_appliesTheMandatoryPiggyback() async {
        let queue = FixQueue()
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        let settingsApplying = FakeDeviceSettingsApplying()
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true), geofenceEtag: "0"))
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: settingsApplying, onReRegisterDevice: {}, onSignedOut: {}
        )

        _ = await runner.runOnce()

        #expect(settingsApplying.appliedSettings == [DeviceSettingsSnapshot(syncIntervalMinutes: 30, trackingEnabled: true)])
    }

    @Test func pausedResponse_appliesSettings_andStopsTheRun() async {
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        let settingsApplying = FakeDeviceSettingsApplying()
        api.reportLocationsHandler = { _, _, _ in
            throw APIError.server(APIErrorBody(code: .trackingPaused, message: "paused", details: [
                "deviceSettings": .object(["syncIntervalMinutes": .number(60), "trackingEnabled": .bool(false)])
            ], requestId: "req_1"), httpStatus: 403)
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: settingsApplying, onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(settingsApplying.appliedSettings == [DeviceSettingsSnapshot(syncIntervalMinutes: 60, trackingEnabled: false)])
    }

    @Test func transientFailure_returnsRetry() async {
        let queue = FixQueue()
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        api.reportLocationsHandler = { _, _, _ in throw APIError.transport("offline") }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .retry)
    }

    @Test func deviceNotFound_callsOnReRegisterDevice() async {
        var reRegisterCallCount = 0
        let queue = FixQueue()
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        api.reportLocationsHandler = { _, _, _ in
            throw APIError.server(APIErrorBody(code: .deviceNotFound, message: "gone", details: nil, requestId: "req_1"), httpStatus: 404)
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), onReRegisterDevice: { reRegisterCallCount += 1 }, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(reRegisterCallCount == 1)
    }

    @Test func signedOut_callsOnSignedOut() async {
        var signedOutCallCount = 0
        let queue = FixQueue()
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        api.reportLocationsHandler = { _, _, _ in
            throw APIError.server(APIErrorBody(code: .authTokenExpired, message: "expired", details: nil, requestId: "req_1"), httpStatus: 401)
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), onReRegisterDevice: {}, onSignedOut: { signedOutCallCount += 1 }
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(signedOutCallCount == 1)
    }

    @Test func rejectedBatch_continuesDrainingTheRemainder() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix())
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        var callCount = 0
        api.reportLocationsHandler = { _, _, fixes in
            callCount += 1
            if callCount == 1 {
                throw APIError.server(APIErrorBody(code: .validationFailed, message: "bad", details: nil, requestId: "req_1"), httpStatus: 400)
            }
            return TestFeatures.envelope(ReportLocationsResponse(accepted: fixes.count, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(callCount == 2, "an unmappable rejection un-freezes the batch (nothing dropped) - the run must retry it within the same cycle")
    }

    // MARK: - I11: geofence-event queue drain + geofenceEtag re-sync trigger (specs/009 §6.2/§6.3)

    @Test func fixSynced_threadsTheGeofenceEtagIntoTheReSyncTrigger() async {
        let queue = FixQueue(generateBatchId: { "batch-1" })
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "\"gf-etag-1\""))
        }
        let geofenceConfigSyncing = FakeGeofenceConfigSyncing()
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), geofenceConfigSyncing: geofenceConfigSyncing,
            onReRegisterDevice: {}, onSignedOut: {}
        )

        _ = await runner.runOnce()

        #expect(geofenceConfigSyncing.syncIfEtagChangedCalls == ["\"gf-etag-1\""])
    }

    @Test func afterDrainingTheFixQueue_alsoDrainsTheGeofenceEventQueue() async {
        // Fix queue empty (.nothingToSync immediately) - the geofence-event drain must still run.
        let api = FakeAPIClient()
        let geofenceEventDraining = FakeGeofenceEventDraining()
        geofenceEventDraining.outcomes = [.nothingToSync]
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(initial: Date()),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: FixQueue(), isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: FixQueue(), apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventDraining: geofenceEventDraining,
            onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(geofenceEventDraining.syncOnceCallCount == 1)
    }

    @Test func geofenceEventSynced_appliesSettings_andThreadsTheGeofenceEtag() async {
        let settingsApplying = FakeDeviceSettingsApplying()
        let geofenceConfigSyncing = FakeGeofenceConfigSyncing()
        let geofenceEventDraining = FakeGeofenceEventDraining()
        geofenceEventDraining.outcomes = [
            .synced(accepted: 1, duplicates: 0, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 20, trackingEnabled: true), geofenceEtag: "\"gf-etag-2\""),
            .nothingToSync
        ]
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(initial: Date()),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: FixQueue(), isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: FixQueue(), apiClient: FakeAPIClient(), deviceId: { "device-1" }),
            settingsApplying: settingsApplying, geofenceConfigSyncing: geofenceConfigSyncing, geofenceEventDraining: geofenceEventDraining,
            onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(settingsApplying.appliedSettings == [DeviceSettingsSnapshot(syncIntervalMinutes: 20, trackingEnabled: true)])
        #expect(geofenceConfigSyncing.syncIfEtagChangedCalls == ["\"gf-etag-2\""])
    }

    @Test func fixQueueTransientFailure_neverAttemptsTheGeofenceEventDrainInTheSameCycle() async {
        let queue = FixQueue()
        await queue.enqueue(makeFix())
        let api = FakeAPIClient()
        api.reportLocationsHandler = { _, _, _ in throw APIError.transport("offline") }
        let geofenceEventDraining = FakeGeofenceEventDraining()
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: queue, isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: queue, apiClient: api, deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventDraining: geofenceEventDraining,
            onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .retry)
        #expect(geofenceEventDraining.syncOnceCallCount == 0, "the fix queue's transient failure backs off the whole run - specs/009 §9")
    }

    @Test func geofenceEventQueueTransientFailure_returnsRetry() async {
        let geofenceEventDraining = FakeGeofenceEventDraining()
        geofenceEventDraining.outcomes = [.transientFailure]
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(initial: Date()),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: FixQueue(), isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: FixQueue(), apiClient: FakeAPIClient(), deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventDraining: geofenceEventDraining,
            onReRegisterDevice: {}, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .retry)
    }

    @Test func geofenceEventDeviceNotFound_callsOnReRegisterDevice() async {
        var reRegisterCallCount = 0
        let geofenceEventDraining = FakeGeofenceEventDraining()
        geofenceEventDraining.outcomes = [.reRegisterDevice]
        let runner = LocationSyncRunner(
            currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: InMemoryLastQueuedFixAtStore(initial: Date()),
            captureCoordinator: FixCaptureCoordinator(provider: FakeLocationProviding(), queue: FixQueue(), isPaused: { true }, isPermissionGranted: { true }),
            syncCoordinator: LocationSyncCoordinator(queue: FixQueue(), apiClient: FakeAPIClient(), deviceId: { "device-1" }),
            settingsApplying: FakeDeviceSettingsApplying(), geofenceEventDraining: geofenceEventDraining,
            onReRegisterDevice: { reRegisterCallCount += 1 }, onSignedOut: {}
        )

        let result = await runner.runOnce()

        #expect(result == .success)
        #expect(reRegisterCallCount == 1)
    }
}
