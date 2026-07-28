import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §6.3 — the tested decision logic behind a region-monitoring
/// enter/exit callback, independent of any real `CLLocationManagerDelegate`/`CLRegion` (those live
/// in the untested `SystemGeofenceRegistrar`). Mirrors Android's `GeofenceTransitionHandlerTest`.
struct GeofenceTransitionHandlerTests {

    private func sequenceIdGenerator(prefix: String) -> () -> String {
        var counter = 0
        return { defer { counter += 1 }; return "\(prefix)-\(counter)" }
    }

    private func makeHandler(
        paused: Bool = false,
        batteryPct: Int = 55,
        now: Date = ISO8601DateFormatter().date(from: "2026-07-27T09:00:00Z")!
    ) -> (handler: GeofenceTransitionHandler, eventQueue: GeofenceEventQueue, fixQueue: FixQueue, provider: FakeLocationProviding) {
        let eventQueue = GeofenceEventQueue(generateBatchId: { "evt-batch" })
        let fixQueue = FixQueue(generateBatchId: { "fix-batch" })
        let provider = FakeLocationProviding() // must never be invoked - the hint short-circuits it
        let captureCoordinator = FixCaptureCoordinator(provider: provider, queue: fixQueue, isPaused: { paused }, isPermissionGranted: { true })
        let handler = GeofenceTransitionHandler(
            eventQueue: eventQueue, fixCaptureCoordinator: captureCoordinator,
            batteryLevelProvider: { batteryPct }, isPaused: { paused },
            eventIdGenerator: sequenceIdGenerator(prefix: "evt"),
            fixIdGenerator: sequenceIdGenerator(prefix: "fix"),
            now: { now }
        )
        return (handler, eventQueue, fixQueue, provider)
    }

    @Test func anEnterCallback_queuesOneEvent() async {
        let (handler, eventQueue, _, _) = makeHandler()
        let event = GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.05, lon: 3.71, accuracyM: 12.0)

        await handler.handle(event)

        let batch = await eventQueue.nextBatchToSend()
        #expect(batch?.events.map(\.geofenceId) == ["gf_home"])
        #expect(batch?.events.allSatisfy { $0.transition == .enter } == true)
        #expect(batch?.events.map(\.eventId) == ["evt-0"])
    }

    @Test func anExitCallback_recordsTheExitTransition() async {
        let (handler, eventQueue, _, _) = makeHandler()
        let event = GeofenceTransitionEvent(geofenceId: "gf_home", transition: .exit, lat: 51.05, lon: 3.71, accuracyM: 12.0)

        await handler.handle(event)

        let batch = await eventQueue.nextBatchToSend()
        #expect(batch?.events.first?.transition == .exit)
    }

    @Test func additionallyQueuesExactlyOneSourceGeofenceFix_usingTheTransitionsOwnCoordinates() async {
        let (handler, _, fixQueue, provider) = makeHandler(batteryPct: 42)
        let event = GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.05, lon: 3.71, accuracyM: 12.0)

        await handler.handle(event)

        let fixBatch = await fixQueue.nextBatchToSend()
        let queuedFix = fixBatch?.fixes.first
        #expect(fixBatch?.fixes.count == 1)
        #expect(queuedFix?.source == .geofence)
        #expect(queuedFix?.lat == 51.05)
        #expect(queuedFix?.lon == 3.71)
        #expect(queuedFix?.accuracyM == 12.0)
        #expect(queuedFix?.batteryPct == 42)
        #expect(provider.requestSingleFixCalls.isEmpty, "the real LocationProviding must never be invoked - the hint short-circuits it")
    }

    @Test func aTransitionDetectedWhilePaused_isDropped_notQueued() async {
        let (handler, eventQueue, fixQueue, _) = makeHandler(paused: true)
        let event = GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.05, lon: 3.71, accuracyM: 12.0)

        await handler.handle(event)

        #expect(await eventQueue.pendingCount() == 0)
        #expect(await fixQueue.queuedCount() == 0)
    }

    @Test func recordedAtIsSharedBetweenTheQueuedEventAndTheFixHint_fromTheSameCallback() async {
        let now = ISO8601DateFormatter().date(from: "2026-07-27T10:15:00Z")!
        let (handler, eventQueue, fixQueue, _) = makeHandler(now: now)
        let event = GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.05, lon: 3.71, accuracyM: 12.0)

        await handler.handle(event)

        let queuedEvent = await eventQueue.nextBatchToSend()?.events.first
        let queuedFix = await fixQueue.nextBatchToSend()?.fixes.first
        #expect(queuedEvent?.recordedAt == "2026-07-27T10:15:00Z")
        #expect(queuedFix?.recordedAt == "2026-07-27T10:15:00Z")
    }

    @Test func eventIdsAreAssignedOnceAtEnqueue_neverRegeneratedAcrossCalls() async {
        let (handler, eventQueue, _, _) = makeHandler()
        await handler.handle(GeofenceTransitionEvent(geofenceId: "gf_home", transition: .enter, lat: 51.0, lon: 3.7, accuracyM: 10))
        await handler.handle(GeofenceTransitionEvent(geofenceId: "gf_work", transition: .exit, lat: 51.1, lon: 3.8, accuracyM: 10))

        let all = await eventQueue.pendingCount()
        #expect(all == 2)
        // Distinct, sequentially-generated ids per callback, not shared/reused.
        let loaded = await eventQueue.nextBatchToSend(maxBatchSize: 20)
        #expect(Set(loaded?.events.map(\.eventId) ?? []).count == 2)
    }
}
