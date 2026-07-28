import Foundation
import Testing
@testable import FindlyKit

private final class FakeBackgroundSyncScheduler: BackgroundSyncScheduling {
    private(set) var scheduleCalls: [TimeInterval?] = []
    private(set) var cancelCallCount = 0
    func scheduleNextSync(afterDelay: TimeInterval?) { scheduleCalls.append(afterDelay) }
    func cancelScheduledSync() { cancelCallCount += 1 }
}

/// specs/009-device-runtime.md §1/§3.4/§4/§9 — the composition root's own orchestration surface
/// (start/stop/background-refresh/foreground), exercised end-to-end against fakes for every
/// CoreLocation/BackgroundTasks-touching collaborator.
@MainActor
struct LocationRuntimeContainerTests {

    func makeFix() -> LocationFix {
        LocationFix(fixId: "f1", recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    @Test func start_whenNotPaused_beginsMonitoringAndSchedulesTheFirstSync() {
        let provider = FakeLocationProviding()
        let scheduler = FakeBackgroundSyncScheduler()
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            locationProvider: provider, backgroundScheduler: scheduler
        )

        container.start()

        #expect(provider.startBackgroundMonitoringCallCount == 1)
        #expect(scheduler.scheduleCalls == [nil])
    }

    @Test func start_whenPaused_doesNotArmMonitoring_butStillSchedulesTheBoundedBackgroundCheck() {
        // Blocking-finding regression test: a cold start that's ALREADY paused (e.g. relaunching
        // after a remote pause applied while the app wasn't running) must still arm the BG task -
        // specs/009 §4's "a low-frequency worker/BG task is the ONLY thing that keeps running
        // while paused" would otherwise never get a first chance to run at all.
        let provider = FakeLocationProviding()
        let scheduler = FakeBackgroundSyncScheduler()
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            locationProvider: provider, backgroundScheduler: scheduler, stateStore: stateStore
        )

        container.start()

        #expect(provider.startBackgroundMonitoringCallCount == 0, "significant-location-change monitoring stays off while paused")
        #expect(scheduler.scheduleCalls == [6 * 60 * 60], "the BG task must still be scheduled, bounded to specs/009 §4's 'at least every 6 hours'")
    }

    @Test func stop_stopsMonitoringAndCancelsTheSchedule() {
        let provider = FakeLocationProviding()
        let scheduler = FakeBackgroundSyncScheduler()
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            locationProvider: provider, backgroundScheduler: scheduler
        )

        container.stop()

        #expect(provider.stopBackgroundMonitoringCallCount == 1)
        #expect(scheduler.cancelCallCount == 1)
    }

    @Test func handleBackgroundRefresh_success_reschedulesWithNoExplicitDelay() async {
        let api = FakeAPIClient()
        let queue0 = InMemoryFixStore()
        queue0.append(makeFix())
        let scheduler = FakeBackgroundSyncScheduler()
        // Pre-seed the cached settings to match exactly what the piggyback will echo, so
        // DeviceSettingsCoordinator sees "nothing changed" and doesn't ALSO reschedule/resume on
        // its own — isolating this assertion to handleBackgroundRefresh's own end-of-run
        // reschedule call (specs/009 §3.4: "rescheduled at the end of every run").
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let container = LocationRuntimeContainer(
            apiClient: api, deviceId: { "device-1" },
            backgroundScheduler: scheduler, fixStore: queue0, stateStore: stateStore
        )

        await container.handleBackgroundRefresh()

        #expect(scheduler.scheduleCalls == [nil])
    }

    @Test func handleBackgroundRefresh_firstEverSettingsApplication_alsoResumesAndReschedules() async {
        // The flip side of the test above, documented explicitly: a device's very FIRST piggyback
        // (no cached settings yet, e.g. right after registration) is treated by
        // SettingsChangeDecision as "everything changed", so DeviceSettingsCoordinator also arms
        // monitoring + reschedules on its own, on top of handleBackgroundRefresh's own end-of-run
        // reschedule. All three calls are idempotent/harmless (re-submitting a BGAppRefreshTask
        // request with the same identifier silently replaces the pending one) - this test exists
        // so that redundancy is a documented, intentional consequence, not a surprise.
        let provider = FakeLocationProviding()
        let api = FakeAPIClient()
        let queue0 = InMemoryFixStore()
        queue0.append(makeFix())
        let scheduler = FakeBackgroundSyncScheduler()
        api.reportLocationsHandler = { _, _, _ in
            TestFeatures.envelope(ReportLocationsResponse(accepted: 1, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let container = LocationRuntimeContainer(
            apiClient: api, deviceId: { "device-1" },
            locationProvider: provider, backgroundScheduler: scheduler, fixStore: queue0
        )

        await container.handleBackgroundRefresh()

        #expect(scheduler.scheduleCalls.allSatisfy { $0 == nil })
        #expect(scheduler.scheduleCalls.count == 3)
        #expect(provider.startBackgroundMonitoringCallCount == 1, "onResume re-arms significant-location-change monitoring")
    }

    @Test func handleBackgroundRefresh_transientFailure_reschedulesWithBackoffDelay() async {
        let api = FakeAPIClient()
        let queue0 = InMemoryFixStore()
        queue0.append(makeFix())
        let scheduler = FakeBackgroundSyncScheduler()
        api.reportLocationsHandler = { _, _, _ in throw APIError.transport("offline") }
        let container = LocationRuntimeContainer(
            apiClient: api, deviceId: { "device-1" },
            backgroundScheduler: scheduler, fixStore: queue0
        )

        await container.handleBackgroundRefresh()

        #expect(scheduler.scheduleCalls == [30], "the first retry backs off 30s (specs/009 §9)")

        await container.handleBackgroundRefresh()

        #expect(scheduler.scheduleCalls == [30, 60], "the second consecutive retry doubles to 60s")
    }

    @Test func handleBackgroundRefresh_successAfterFailures_resetsTheBackoffCounter() async {
        let api = FakeAPIClient()
        let queue0 = InMemoryFixStore()
        queue0.append(makeFix())
        let scheduler = FakeBackgroundSyncScheduler()
        var shouldFail = true
        api.reportLocationsHandler = { _, _, fixes in
            if shouldFail { throw APIError.transport("offline") }
            return TestFeatures.envelope(ReportLocationsResponse(accepted: fixes.count, duplicates: 0, lastKnownUpdated: true, deviceSettings: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true), geofenceEtag: "0"))
        }
        let container = LocationRuntimeContainer(
            apiClient: api, deviceId: { "device-1" },
            backgroundScheduler: scheduler, fixStore: queue0
        )
        await container.handleBackgroundRefresh() // fails once -> attempt count 1
        shouldFail = false
        await container.handleBackgroundRefresh() // succeeds -> resets to 0
        shouldFail = true
        queue0.append(makeFix())

        await container.handleBackgroundRefresh() // fails again -> should be attempt 1 again, not 3

        #expect(scheduler.scheduleCalls.last == 30, "the counter must reset after a success, not keep climbing")
    }

    // MARK: - Blocking finding: the paused device must self-heal via the BG task (specs/009 §4)

    @Test func handleBackgroundRefresh_whilePaused_pollsInsteadOfSyncing_andNeverAttemptsAFlush() async {
        let api = FakeAPIClient()
        var listDevicesCallCount = 0
        api.listDevicesHandler = {
            listDevicesCallCount += 1
            return TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "device-1", ownerUserId: "user-1", platform: "ios", deviceName: "iPhone",
                    model: "iPhone15,2", appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: false,
                    pushInvalid: false, ownerDisplayName: "Alex", lastSeenAt: "2026-07-19T09:00:00Z"
                )
            ]))
        }
        let scheduler = FakeBackgroundSyncScheduler()
        let queue0 = InMemoryFixStore()
        queue0.append(makeFix()) // a pre-pause fix, must stay queued and untouched
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))
        let container = LocationRuntimeContainer(
            apiClient: api, deviceId: { "device-1" },
            backgroundScheduler: scheduler, fixStore: queue0, stateStore: stateStore
        )

        await container.handleBackgroundRefresh()

        #expect(listDevicesCallCount == 1, "must poll GET /devices while paused (specs/009 §4)")
        #expect(api.reportLocationsCalls.isEmpty, "a paused device must not attempt to flush at all")
        #expect(queue0.loadAll().count == 1, "pre-pause fixes stay queued, untouched")
    }

    @Test func handleBackgroundRefresh_whilePaused_reschedulesBoundedToAtLeastSixHours() async {
        // The specific numeric bound specs/009 §12 calls out as a required test case.
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "device-1", ownerUserId: "user-1", platform: "ios", deviceName: "iPhone",
                    model: "iPhone15,2", appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: false,
                    pushInvalid: false, ownerDisplayName: "Alex", lastSeenAt: "2026-07-19T09:00:00Z"
                )
            ]))
        }
        let scheduler = FakeBackgroundSyncScheduler()
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))
        let container = LocationRuntimeContainer(apiClient: api, deviceId: { "device-1" }, backgroundScheduler: scheduler, stateStore: stateStore)

        await container.handleBackgroundRefresh()

        #expect(scheduler.scheduleCalls == [6 * 60 * 60], "specs/009 §4: 'at least every 6 hours'")
    }

    @Test func handleBackgroundRefresh_pausedPollDetectsResume_reschedulesImmediately_notSixHoursOut() async {
        let provider = FakeLocationProviding()
        let api = FakeAPIClient()
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "device-1", ownerUserId: "user-1", platform: "ios", deviceName: "iPhone",
                    model: "iPhone15,2", appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: true,
                    pushInvalid: false, ownerDisplayName: "Alex", lastSeenAt: "2026-07-19T09:00:00Z"
                )
            ]))
        }
        let scheduler = FakeBackgroundSyncScheduler()
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))
        let container = LocationRuntimeContainer(
            apiClient: api, deviceId: { "device-1" },
            locationProvider: provider, backgroundScheduler: scheduler, stateStore: stateStore
        )

        await container.handleBackgroundRefresh()

        #expect(stateStore.current()?.trackingEnabled == true)
        #expect(provider.startBackgroundMonitoringCallCount == 1, "the detected resume must re-arm significant-location-change monitoring")
        #expect(scheduler.scheduleCalls.allSatisfy { $0 == nil }, "a detected resume reschedules immediately, never with the paused 6h bound")
        #expect(!scheduler.scheduleCalls.isEmpty)
    }

    @Test func onAppForeground_pollsPausedSettings_andRunsTheSyncCycle() async {
        let api = FakeAPIClient()
        var listDevicesCallCount = 0
        api.listDevicesHandler = {
            listDevicesCallCount += 1
            return TestFeatures.envelope(ListDevicesResponse(devices: []))
        }
        let container = LocationRuntimeContainer(apiClient: api, deviceId: { "device-1" })

        await container.onAppForeground()

        #expect(listDevicesCallCount == 1)
    }
}
