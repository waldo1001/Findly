import Foundation
import Testing
@testable import FindlyKit

private final class FakeBackgroundSyncScheduler: BackgroundSyncScheduling {
    private(set) var scheduleCalls: [TimeInterval?] = []
    private(set) var cancelCallCount = 0
    func scheduleNextSync(afterDelay: TimeInterval?) { scheduleCalls.append(afterDelay) }
    func cancelScheduledSync() { cancelCallCount += 1 }
}

/// **Post-review addition (concurrency re-review).** Widens the window between
/// `wipeLocalState()`'s own actor-hop suspension points and a concurrently-firing transition, so
/// `wipeLocalState_racingAConcurrentTransition_stillDropsIt` can reliably interleave them without
/// depending on winning an unlikely scheduling coin-flip — mirrors a slow on-disk `SQLiteFixStore.
/// removeAll()` genuinely taking wall-clock time (specs/009 §2), rather than the in-memory store's
/// effectively-instant one. `Thread.sleep` is deliberate here (not `Task.sleep`): it blocks this
/// call's own synchronous execution exactly the way a real blocking disk write would, without
/// itself introducing a new `await`/suspension point that would change what's being tested.
private final class DelayedFixStore: FixStoring {
    private let wrapped = InMemoryFixStore()
    private let delaySeconds: TimeInterval
    init(delaySeconds: TimeInterval) { self.delaySeconds = delaySeconds }
    func loadAll() -> [LocationFix] { wrapped.loadAll() }
    @discardableResult func append(_ fix: LocationFix) -> Int { wrapped.append(fix) }
    func remove(fixIds: Set<String>) { wrapped.remove(fixIds: fixIds) }
    func currentBatch() -> PendingBatch? { wrapped.currentBatch() }
    func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> PendingBatch? { wrapped.freezeNextBatch(maxSize: maxSize, newBatchId: newBatchId) }
    func markAccepted(batchId: String) { wrapped.markAccepted(batchId: batchId) }
    func markRejected(batchId: String, dropFixIds: Set<String>?) { wrapped.markRejected(batchId: batchId, dropFixIds: dropFixIds) }
    func removeAll() {
        Thread.sleep(forTimeInterval: delaySeconds)
        wrapped.removeAll()
    }
}

/// The `GeofenceEventQueueStoring` counterpart to `DelayedFixStore` above — same rationale, mirrors
/// a slow `SQLiteGeofenceEventQueueStore.removeAll()`.
private final class DelayedGeofenceEventQueueStore: GeofenceEventQueueStoring {
    private let wrapped = InMemoryGeofenceEventQueueStore()
    private let delaySeconds: TimeInterval
    init(delaySeconds: TimeInterval) { self.delaySeconds = delaySeconds }
    func loadAll() -> [GeofenceEventReport] { wrapped.loadAll() }
    func enqueue(_ event: GeofenceEventReport) { wrapped.enqueue(event) }
    func currentBatch() -> GeofenceEventBatch? { wrapped.currentBatch() }
    func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> GeofenceEventBatch? { wrapped.freezeNextBatch(maxSize: maxSize, newBatchId: newBatchId) }
    func markSent(batchId: String) { wrapped.markSent(batchId: batchId) }
    func markFailedTransient(batchId: String) { wrapped.markFailedTransient(batchId: batchId) }
    func removeAll() {
        Thread.sleep(forTimeInterval: delaySeconds)
        wrapped.removeAll()
    }
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
        #expect(scheduler.scheduleCalls == [TimeInterval(6 * 60 * 60)], "the BG task must still be scheduled, bounded to specs/009 §4's 'at least every 6 hours'")
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
        // I11: the accepted-flush piggyback now also triggers a geofenceEtag mismatch check
        // (nothing cached yet, "0" != nil) - stub the resulting GET /geofences call.
        api.getGeofencesHandler = { _ in .notModified }
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
        // I11: this test's "everything changed" first-ever settings application triggers BOTH
        // onResume's geofence re-sync AND the accepted-flush geofenceEtag mismatch check - stub
        // the resulting GET /geofences call(s).
        api.getGeofencesHandler = { _ in .notModified }
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
        // I11: the eventual accepted flush's geofenceEtag mismatch check needs a stub too.
        api.getGeofencesHandler = { _ in .notModified }
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

        #expect(scheduler.scheduleCalls == [TimeInterval(6 * 60 * 60)], "specs/009 §4: 'at least every 6 hours'")
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
        // I11: the detected resume triggers onResume's geofence config re-sync (specs/009 §6.2).
        api.getGeofencesHandler = { _ in .notModified }
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

    // MARK: - I11: geofence config sync triggers (specs/009 §6.2)

    @Test func syncGeofenceConfigOnColdStart_notPaused_registersFromTheFreshlyFetchedConfig() async {
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in
            getGeofencesCallCount += 1
            return .ok(GeofenceConfig(version: 1, geofences: []), etag: "\"0x1\"", features: TestFeatures.free)
        }
        let registrar = FakeGeofenceRegistering()
        let container = LocationRuntimeContainer(apiClient: api, deviceId: { "device-1" }, geofenceRegistrar: registrar)

        await container.syncGeofenceConfigOnColdStart()

        #expect(getGeofencesCallCount == 1)
        #expect(registrar.registerAllCalls.count == 1)
    }

    @Test func syncGeofenceConfigOnColdStart_paused_isANoOp() async {
        // specs/009 §4: a paused device has zero geofences registered by contract - cold start
        // must not re-register while still paused.
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in getGeofencesCallCount += 1; return .notModified }
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))
        let container = LocationRuntimeContainer(apiClient: api, deviceId: { "device-1" }, stateStore: stateStore)

        await container.syncGeofenceConfigOnColdStart()

        #expect(getGeofencesCallCount == 0)
    }

    @Test func onSignedIn_notPaused_syncsGeofenceConfig() async {
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in getGeofencesCallCount += 1; return .notModified }
        let container = LocationRuntimeContainer(apiClient: api, deviceId: { "device-1" })

        await container.onSignedIn()

        #expect(getGeofencesCallCount == 1)
    }

    @Test func resumeFromPause_alsoReSyncsGeofenceConfig() async {
        // specs/009 §6.2: "resume from pause" is one of the five re-registration triggers - wired
        // via DeviceSettingsCoordinator's onResume seam.
        let api = FakeAPIClient()
        var getGeofencesCallCount = 0
        api.getGeofencesHandler = { _ in getGeofencesCallCount += 1; return .notModified }
        api.listDevicesHandler = {
            TestFeatures.envelope(ListDevicesResponse(devices: [
                DeviceListItem(
                    deviceId: "device-1", ownerUserId: "user-1", platform: "ios", deviceName: "iPhone",
                    model: "iPhone15,2", appVersion: "1.0.0", syncIntervalMinutes: 15, trackingEnabled: true,
                    pushInvalid: false, ownerDisplayName: "Alex", lastSeenAt: "2026-07-19T09:00:00Z"
                )
            ]))
        }
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: false))
        let container = LocationRuntimeContainer(apiClient: api, deviceId: { "device-1" }, stateStore: stateStore)

        await container.onAppForeground() // polls GET /devices -> observes the resume

        #expect(stateStore.current()?.trackingEnabled == true)
        #expect(getGeofencesCallCount == 1)
    }

    @Test func geofenceTransitionHandler_isExposedAndSharesTheContainersFixCaptureCoordinator() async {
        // A smoke test that the exposed handler is genuinely wired to this container's own
        // fixQueue/geofenceEventQueue - a full behavioral suite lives in
        // GeofenceTransitionHandlerTests; this just proves the composition-root wiring is correct.
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            isPermissionGranted: { true }
        )

        await container.geofenceTransitionHandler.handle(
            GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.0, lon: 3.7, accuracyM: 10)
        )

        #expect(await container.geofenceEventQueue.pendingCount() == 1)
        #expect(await container.fixQueue.queuedCount() == 1)
    }

    // MARK: - Post-review: wipeLocalState() (security review, High finding — no local state was
    // wiped on sign-out, only on account deletion, a real deterministic cross-account data leak)

    @Test func wipeLocalState_clearsEveryPieceOfLocalStateItClaimsTo() async {
        let provider = FakeLocationProviding()
        let scheduler = FakeBackgroundSyncScheduler()
        let registrar = FakeGeofenceRegistering()
        let geofenceConfigStore = InMemoryGeofenceConfigStateStore(
            initial: CachedGeofenceConfig(etag: "\"0x1\"", geofences: [])
        )
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            locationProvider: provider, backgroundScheduler: scheduler,
            stateStore: stateStore, geofenceRegistrar: registrar, geofenceConfigStore: geofenceConfigStore
        )
        await container.fixQueue.enqueue(makeFix())
        await container.geofenceEventQueue.enqueue(
            GeofenceEventReport(eventId: "e1", geofenceId: "gf_home", transition: .enter, recordedAt: "2026-07-19T09:00:00Z")
        )

        await container.wipeLocalState()

        #expect(await container.fixQueue.queuedCount() == 0, "the fix queue must be cleared")
        #expect(await container.geofenceEventQueue.pendingCount() == 0, "the geofence-event queue must be cleared")
        #expect(geofenceConfigStore.current() == nil, "the cached geofence config/ETag must be cleared")
        #expect(
            stateStore.current()?.trackingEnabled == false,
            "cached device settings must read as a DEFINITE paused state, not merely 'unknown' — see DeviceSettingsStateStoring.clear()'s doc for why nil alone wouldn't be enough"
        )
        #expect(registrar.unregisterAllCallCount == 1, "the registered CLLocationManager geofences must be unregistered")
        #expect(provider.stopBackgroundMonitoringCallCount == 1, "significant-location-change monitoring must stop")
        #expect(scheduler.cancelCallCount == 1, "the scheduled BGAppRefreshTask must be canceled")
    }

    /// I31 (mirrors A25's Major 2, 009 §7): the permission-disclosure decline/acknowledgement state
    /// MUST be wiped by the REAL account-deletion path, not a documented-but-uncalled `clear()` —
    /// I26's exact pattern. Proving it here (against the container's own `wipeLocalState()`, the
    /// method `DeleteAccountViewModel`'s `wipeLocalState` closure and the forced-sign-out/
    /// sign-out-for-retry paths all actually call) is what makes this a live caller, not a promise.
    @Test func wipeLocalState_clearsThePermissionDisclosureState() async {
        let store = InMemoryPermissionDisclosureStore()
        store.acknowledge(.foreground)
        store.decline(.background)
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            permissionDisclosureStore: store
        )

        await container.wipeLocalState()

        #expect(store.isAcknowledged(.foreground) == false, "a different user on this device must see the disclosure again")
        #expect(store.isDeclined(.background) == false, "the decline is consent, not a device-level preference — it must not survive account deletion either")
    }

    /// specs/010-app-shell-and-screen-ux.md §1.2 (I34 review fix — High: a real cross-account data
    /// leak). `FamilyContextCache.clear()`'s own doc said it existed "as part of the account-
    /// deletion/sign-out local wipe" — I26's exact pattern (a documented `clear()` nothing calls),
    /// reproduced in brand-new code. `familyContextCache` is a process-lifetime `@StateObject`, so
    /// without this a signed-out user's family name/display name/role would keep rendering in the
    /// NEXT signed-in user's drawer header on the same device until some later probe happened to
    /// overwrite it. Proving it here (against the container's own `wipeLocalState()`, the method
    /// every real sign-out/account-deletion path funnels through) is what makes this a live
    /// caller, not a promise — same rationale as `wipeLocalState_clearsThePermissionDisclosureState`
    /// immediately above.
    @Test func wipeLocalState_clearsTheFamilyContextCache() async {
        let cache = FamilyContextCache()
        cache.update(familyName: "Wauters", myDisplayName: "Eric", isParent: true)
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            familyContextCache: cache
        )

        await container.wipeLocalState()

        #expect(cache.familyName == nil, "a different signed-in user on this device must never see the previous caller's family name")
        #expect(cache.myDisplayName == nil, "nor their display name")
        #expect(cache.isParent == nil, "nor their role")
    }

    /// I26 (specs/008-privacy-endpoints.md §4.4): `LastQueuedFixAtStoring` previously had NO clear
    /// capability at all — its single sync-rate-limiting timestamp (specs/009 §3.4) survived every
    /// sign-out and account deletion. Proving this against the container's own `wipeLocalState()`
    /// (rather than calling `store.clear()` directly) is what makes this a live-called step of the
    /// real wipe, not merely a method that works in isolation — same rationale as the two
    /// `wipeLocalState_clearsThe...` tests immediately above.
    @Test func wipeLocalState_clearsTheLastQueuedFixAtStore() async {
        let store = InMemoryLastQueuedFixAtStore(initial: Date(timeIntervalSince1970: 1_700_000_000))
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            lastQueuedFixAtStore: store
        )

        await container.wipeLocalState()

        #expect(store.lastQueuedFixAt() == nil, "a different signed-in user on this device must not inherit the previous caller's sync-rate-limiting timestamp")
    }

    @Test func wipeLocalState_calledTwice_isIdempotentSafe() async {
        let registrar = FakeGeofenceRegistering()
        let container = LocationRuntimeContainer(apiClient: FakeAPIClient(), deviceId: { "device-1" }, geofenceRegistrar: registrar)

        await container.wipeLocalState()
        await container.wipeLocalState()

        #expect(registrar.unregisterAllCallCount == 2, "each call performs its own unregister — no crash/inconsistency from calling twice")
        #expect(await container.fixQueue.queuedCount() == 0)
    }

    /// The concrete acceptance criterion for the security review's High finding: a geofence
    /// transition delegate callback that fires AFTER `wipeLocalState()` returns (the exact race
    /// specs/009 §6.2 already accepts as normal — the platform unregister call and the callback
    /// aren't atomic) must be dropped, not durably queued under whatever *different* account signs
    /// in next.
    @Test func wipeLocalState_thenATransitionArrives_isDroppedNotQueued() async {
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" }, stateStore: stateStore,
            isPermissionGranted: { true }
        )

        await container.wipeLocalState()
        await container.geofenceTransitionHandler.handle(
            GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.0, lon: 3.7, accuracyM: 10)
        )

        #expect(await container.geofenceEventQueue.pendingCount() == 0, "a transition detected after wipeLocalState() must be dropped, not queued")
        #expect(await container.fixQueue.queuedCount() == 0, "the accompanying source: .geofence fix must also be dropped")
    }

    /// **Post-review addition (concurrency re-review).** The sequential test above only proves the
    /// already-easy case (wipe fully completes, THEN a transition arrives) — it never exercises the
    /// real-world delivery mechanism: `SystemGeofenceRegistrar.forwardTransition` fires a transition
    /// via an **unstructured** `Task { await transitionHandler?.handle(event) }`, decoupled from
    /// `wipeLocalState()`'s own isolation and step order. Before the fix (`stateStore.clear()`
    /// moved to be `wipeLocalState()`'s FIRST step, synchronous, before either SQLite-backed
    /// `await`), a transition racing those suspension points could read the still-stale
    /// `trackingEnabled: true`, enqueue its event, and have that enqueue land on the
    /// `GeofenceEventQueue`/`FixQueue` actor's mailbox AFTER the corresponding `clearAll()` call had
    /// already run — surviving `wipeLocalState()` entirely. `DelayedFixStore`/
    /// `DelayedGeofenceEventQueueStore` widen that window to make the race deterministic to test
    /// rather than a coin-flip; the 5 ms head start below lands comfortably inside the 50 ms delay,
    /// simulating "a transition fires right after `unregisterAll()`" — exactly the scenario the
    /// security review's concurrency walkthrough described.
    @Test func wipeLocalState_racingAConcurrentTransition_stillDropsIt() async {
        let stateStore = InMemoryDeviceSettingsStateStore(initial: DeviceSettingsSnapshot(syncIntervalMinutes: 15, trackingEnabled: true))
        let container = LocationRuntimeContainer(
            apiClient: FakeAPIClient(), deviceId: { "device-1" },
            fixStore: DelayedFixStore(delaySeconds: 0.05),
            stateStore: stateStore,
            geofenceRegistrar: FakeGeofenceRegistering(),
            geofenceEventStore: DelayedGeofenceEventQueueStore(delaySeconds: 0.05),
            isPermissionGranted: { true }
        )
        let event = GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.0, lon: 3.7, accuracyM: 10)

        async let wipe: () = container.wipeLocalState()
        async let racedTransition: () = {
            // A brief head start so wipeLocalState()'s Task has actually begun executing (and, per
            // the fix, already run its synchronous stateStore.clear()) by the time the transition's
            // own isPaused() check runs, while wipeLocalState() itself is still mid-flight in its
            // (deliberately slowed) queue-clearing awaits.
            try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms, well inside the 50 ms store delay
            await container.geofenceTransitionHandler.handle(event)
        }()
        _ = await (wipe, racedTransition)

        #expect(await container.geofenceEventQueue.pendingCount() == 0, "a transition racing wipeLocalState()'s own suspension points must still be dropped, not leaked into whichever session signs in next")
        #expect(await container.fixQueue.queuedCount() == 0)
    }
}
