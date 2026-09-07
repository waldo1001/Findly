import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §1.2 (suppression) + §1.1 (accuracy tiers, tested separately in
/// `FixAccuracyPolicyTests`) — mirrors Android's `FixCaptureCoordinatorTest.kt` coverage.
/// I53 - @MainActor: constructs FakeLocationProviding, now inferred @MainActor from LocationProviding.
@MainActor
struct FixCaptureCoordinatorTests {

    func makeFix(lat: Double = 51.0, lon: Double = 3.7, recordedAt: String = "2026-07-19T09:00:00Z") -> LocationFix {
        LocationFix(fixId: UUID().uuidString, recordedAt: recordedAt, lat: lat, lon: lon, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    fileprivate func makeCoordinator(
        provider: FakeLocationProviding,
        store: InMemoryFixStore = InMemoryFixStore(),
        isPaused: @escaping () -> Bool = { false },
        isPermissionGranted: @escaping () -> Bool = { true },
        currentSyncIntervalMinutes: (() -> Int)? = nil,
        lastQueuedFixAtStore: LastQueuedFixAtStoring? = nil,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000_000) }
    ) -> (FixCaptureCoordinator, FixQueue, InMemoryFixStore) {
        let queue = FixQueue(store: store)
        let coordinator = FixCaptureCoordinator(
            provider: provider, queue: queue, isPaused: isPaused, isPermissionGranted: isPermissionGranted,
            currentSyncIntervalMinutes: currentSyncIntervalMinutes, lastQueuedFixAtStore: lastQueuedFixAtStore, now: now
        )
        return (coordinator, queue, store)
    }

    @Test func capturesAndQueuesAFix_whenNotPausedAndPermissionGranted() async {
        let provider = FakeLocationProviding()
        provider.nextFix = .success(makeFix())
        let (coordinator, _, store) = makeCoordinator(provider: provider)

        let result = await coordinator.captureAndQueue(source: .periodic)

        #expect(result != nil)
        #expect(store.loadAll().count == 1)
        #expect(provider.requestSingleFixCalls == [.periodic])
    }

    @Test func paused_skipsCapture_neverInvokesTheProvider() async {
        let provider = FakeLocationProviding()
        provider.nextFix = .success(makeFix())
        let (coordinator, _, store) = makeCoordinator(provider: provider, isPaused: { true })

        let result = await coordinator.captureAndQueue(source: .periodic)

        #expect(result == nil)
        #expect(store.loadAll().isEmpty)
        #expect(provider.requestSingleFixCalls.isEmpty, "no GPS burn while paused")
    }

    @Test func permissionAbsent_skipsCapture_neverInvokesTheProvider() async {
        let provider = FakeLocationProviding()
        provider.nextFix = .success(makeFix())
        let (coordinator, _, store) = makeCoordinator(provider: provider, isPermissionGranted: { false })

        let result = await coordinator.captureAndQueue(source: .periodic)

        #expect(result == nil)
        #expect(store.loadAll().isEmpty)
        #expect(provider.requestSingleFixCalls.isEmpty)
    }

    @Test func providerThrows_returnsNilSilently_neverPropagatesAnError() async {
        let provider = FakeLocationProviding()
        provider.nextFix = .failure(LocationProvidingError.timedOut)
        let (coordinator, _, store) = makeCoordinator(provider: provider)

        let result = await coordinator.captureAndQueue(source: .periodic)

        #expect(result == nil)
        #expect(store.loadAll().isEmpty)
    }

    @Test func identicalPositionWithin60Seconds_isDebounced() async {
        let provider = FakeLocationProviding()
        var now = Date(timeIntervalSince1970: 1_000_000)
        provider.nextFix = .success(makeFix(lat: 51.0, lon: 3.7))
        let (coordinator, _, store) = makeCoordinator(provider: provider, now: { now })

        _ = await coordinator.captureAndQueue(source: .periodic)
        now = now.addingTimeInterval(30) // < 60s later, same position
        provider.nextFix = .success(makeFix(lat: 51.0, lon: 3.7))
        let second = await coordinator.captureAndQueue(source: .periodic)

        #expect(second == nil)
        #expect(store.loadAll().count == 1)
    }

    @Test func identicalPositionAfter60Seconds_isNotDebounced() async {
        let provider = FakeLocationProviding()
        var now = Date(timeIntervalSince1970: 1_000_000)
        provider.nextFix = .success(makeFix(lat: 51.0, lon: 3.7))
        let (coordinator, _, store) = makeCoordinator(provider: provider, now: { now })

        _ = await coordinator.captureAndQueue(source: .periodic)
        now = now.addingTimeInterval(60)
        provider.nextFix = .success(makeFix(lat: 51.0, lon: 3.7))
        let second = await coordinator.captureAndQueue(source: .periodic)

        #expect(second != nil)
        #expect(store.loadAll().count == 2)
    }

    @Test func differentPositionWithin60Seconds_isNotDebounced() async {
        let provider = FakeLocationProviding()
        let now = Date(timeIntervalSince1970: 1_000_000)
        provider.nextFix = .success(makeFix(lat: 51.0, lon: 3.7))
        let (coordinator, _, store) = makeCoordinator(provider: provider, now: { now })

        _ = await coordinator.captureAndQueue(source: .periodic)
        provider.nextFix = .success(makeFix(lat: 52.0, lon: 3.7))
        let second = await coordinator.captureAndQueue(source: .periodic)

        #expect(second != nil)
        #expect(store.loadAll().count == 2)
    }

    @Test func hint_shortCircuitsTheProvider_neverBurnsGPS() async {
        let provider = FakeLocationProviding()
        let (coordinator, _, store) = makeCoordinator(provider: provider)
        let hint = makeFix(lat: 51.5, lon: 3.9)

        let result = await coordinator.captureAndQueue(source: .geofence, hint: hint)

        #expect(result == hint)
        #expect(store.loadAll() == [hint])
        #expect(provider.requestSingleFixCalls.isEmpty, "a hint must short-circuit an actual GPS request")
    }

    @Test func hint_stillSuppressedWhenPaused() async {
        let provider = FakeLocationProviding()
        let (coordinator, _, store) = makeCoordinator(provider: provider, isPaused: { true })

        let result = await coordinator.captureAndQueue(source: .geofence, hint: makeFix())

        #expect(result == nil)
        #expect(store.loadAll().isEmpty)
    }

    // I50 review Minor finding 6 — the significant-location-change/visit hint paths
    // (LocationProviding.swift's didUpdateLocations/didVisit) call captureAndQueue(source:
    // .periodic, hint:) directly, bypassing SyncTriggerPolicy's × 0.8 elapsed-time gate and never
    // recording lastQueuedFixAt - so a hint-triggered fix was queued regardless of interval AND
    // left the timestamp stale, making the very next background-refresh trigger capture again
    // immediately. Applying the gate HERE, inside the one seam every `.periodic` caller goes
    // through (including LocationSyncRunner's own, already-gated call), fixes both hint paths for
    // free without either needing to know about SyncTriggerPolicy itself. Both new params are
    // optional/nil-defaulted so the many existing callers above (which never configure this) are
    // completely unaffected — the gate is simply never applied when either is nil.

    @Test func periodicHint_belowTheEightyPercentThreshold_isSuppressed() async {
        let provider = FakeLocationProviding()
        let lastQueuedFixAtStore = InMemoryLastQueuedFixAtStore(initial: Date(timeIntervalSince1970: 1_000_000))
        let (coordinator, _, store) = makeCoordinator(
            provider: provider,
            currentSyncIntervalMinutes: { 15 }, // threshold = 15 * 60 * 0.8 = 720s
            lastQueuedFixAtStore: lastQueuedFixAtStore,
            now: { Date(timeIntervalSince1970: 1_000_030) } // only 30s elapsed
        )

        let result = await coordinator.captureAndQueue(source: .periodic, hint: makeFix())

        #expect(result == nil, "a hint-triggered periodic capture arriving before the 0.8 elapsed threshold must be suppressed, exactly like LocationSyncRunner's own gate")
        #expect(store.loadAll().isEmpty)
        #expect(provider.requestSingleFixCalls.isEmpty)
    }

    @Test func periodicHint_aboveTheEightyPercentThreshold_recordsLastQueuedFixAtOnSuccess() async {
        let provider = FakeLocationProviding()
        let lastQueuedFixAtStore = InMemoryLastQueuedFixAtStore(initial: Date(timeIntervalSince1970: 1_000_000))
        let now = Date(timeIntervalSince1970: 1_000_800) // 800s elapsed > 720s threshold
        let (coordinator, _, store) = makeCoordinator(
            provider: provider,
            currentSyncIntervalMinutes: { 15 },
            lastQueuedFixAtStore: lastQueuedFixAtStore,
            now: { now }
        )

        let result = await coordinator.captureAndQueue(source: .periodic, hint: makeFix())

        #expect(result != nil)
        #expect(store.loadAll().count == 1)
        #expect(lastQueuedFixAtStore.lastQueuedFixAt() == now, "a successful hint-triggered enqueue must record lastQueuedFixAt, or the very next background-refresh trigger captures again immediately")
    }

    @Test func periodicHint_withNoLastQueuedFixAtRecorded_isNeverSuppressed() async {
        // SyncTriggerPolicy.shouldCapture treats "never captured before" as always-eligible.
        let provider = FakeLocationProviding()
        let lastQueuedFixAtStore = InMemoryLastQueuedFixAtStore(initial: nil)
        let (coordinator, _, store) = makeCoordinator(
            provider: provider, currentSyncIntervalMinutes: { 15 }, lastQueuedFixAtStore: lastQueuedFixAtStore
        )

        let result = await coordinator.captureAndQueue(source: .periodic, hint: makeFix())

        #expect(result != nil)
        #expect(store.loadAll().count == 1)
    }

    @Test func nonPeriodicHint_isNeverGatedByTheElapsedThreshold_norRecordsLastQueuedFixAt() async {
        let provider = FakeLocationProviding()
        let lastQueuedFixAtStore = InMemoryLastQueuedFixAtStore(initial: Date(timeIntervalSince1970: 1_000_000))
        let (coordinator, _, store) = makeCoordinator(
            provider: provider,
            currentSyncIntervalMinutes: { 15 },
            lastQueuedFixAtStore: lastQueuedFixAtStore,
            now: { Date(timeIntervalSince1970: 1_000_001) } // 1s elapsed - would fail the periodic gate
        )

        let result = await coordinator.captureAndQueue(source: .geofence, hint: makeFix())

        #expect(result != nil, "the elapsed-time rule is specs/009 §3.4's iOS *periodic*-trigger gate only - geofence/manual/locate captures are unaffected")
        #expect(store.loadAll().count == 1)
        #expect(lastQueuedFixAtStore.lastQueuedFixAt() == Date(timeIntervalSince1970: 1_000_000), "non-periodic sources must not touch lastQueuedFixAt either")
    }

    @Test func pauseArrivingMidCapture_dropsTheResult_neverQueuesIt() async {
        // isPaused() is called BEFORE capture (false) and AFTER (true) - simulating a pause
        // landing while the GPS request was in flight (specs/009 §4: "in-flight captures dropped,
        // not queued").
        var callCount = 0
        let provider = FakeLocationProviding()
        provider.nextFix = .success(makeFix())
        let (coordinator, _, store) = makeCoordinator(provider: provider, isPaused: {
            callCount += 1
            return callCount > 1
        })

        let result = await coordinator.captureAndQueue(source: .periodic)

        #expect(result == nil)
        #expect(store.loadAll().isEmpty)
    }
}
