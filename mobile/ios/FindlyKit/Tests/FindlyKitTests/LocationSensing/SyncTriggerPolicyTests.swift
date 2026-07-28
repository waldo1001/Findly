import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §3.4 — "A capture is taken when a trigger fires AND at least
/// `syncIntervalMinutes × 0.8` has elapsed since the last queued fix." Pure decision logic, no
/// BackgroundTasks/CoreLocation involved.
struct SyncTriggerPolicyTests {

    @Test func noPriorFix_alwaysCaptures() {
        let now = Date()
        #expect(SyncTriggerPolicy.shouldCapture(syncIntervalMinutes: 15, lastQueuedFixAt: nil, now: now))
    }

    @Test func exactlyAtTheEightyPercentThreshold_captures() {
        let now = Date()
        // 15 min * 0.8 = 12 min = 720s
        let lastQueuedFixAt = now.addingTimeInterval(-720)
        #expect(SyncTriggerPolicy.shouldCapture(syncIntervalMinutes: 15, lastQueuedFixAt: lastQueuedFixAt, now: now))
    }

    @Test func justBeforeTheEightyPercentThreshold_doesNotCapture() {
        let now = Date()
        let lastQueuedFixAt = now.addingTimeInterval(-719)
        #expect(!SyncTriggerPolicy.shouldCapture(syncIntervalMinutes: 15, lastQueuedFixAt: lastQueuedFixAt, now: now))
    }

    @Test func wellPastTheThreshold_captures() {
        let now = Date()
        let lastQueuedFixAt = now.addingTimeInterval(-3600)
        #expect(SyncTriggerPolicy.shouldCapture(syncIntervalMinutes: 15, lastQueuedFixAt: lastQueuedFixAt, now: now))
    }

    @Test func aLargeInterval_scalesTheThresholdProportionally() {
        let now = Date()
        // 1440 min * 0.8 = 1152 min = 69120s
        let justUnder = now.addingTimeInterval(-69119)
        let justOver = now.addingTimeInterval(-69120)
        #expect(!SyncTriggerPolicy.shouldCapture(syncIntervalMinutes: 1440, lastQueuedFixAt: justUnder, now: now))
        #expect(SyncTriggerPolicy.shouldCapture(syncIntervalMinutes: 1440, lastQueuedFixAt: justOver, now: now))
    }
}
