import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §1.1, specs/001-api-contract.md §5.1 `source` (I54 — I50 fix 8
/// regression). `PresenceAccuracyPolicy.drainAction` correctly stops
/// `SystemLocationProvider.applyDrainAction()` from calling `manager.stopUpdatingLocation()` when a
/// caller's own timeout drains the pending registry while the §1.3 presence session is active
/// (`.resetAccuracyToPresenceBaseline` instead of `.stopUpdating` — stopping would tear down
/// presence's own continuous stream, since both share one `CLLocationManager`). That correctly
/// protects presence, but it means CoreLocation's `requestLocation()` is never actually cancelled —
/// it eventually delivers anyway, to an already-empty pending registry, and used to fall through to
/// the significant-location-change/visit "hint" path mislabeled `source: "periodic"`, even when a
/// `.locate`/`.manual`/`.geofence` request is what actually triggered it. 001 §5.1's `source` is
/// meant to say what triggered the capture.
///
/// `StaleDeliveryPolicy` is the pure decision logic: `SystemLocationProvider` bumps a monotonic
/// `requestGeneration` every time it actually issues a fresh `requestLocation()`
/// (`PendingFixContinuations.registerAndAct`'s `action` closure). When a caller's own timeout drains
/// the registry (`PendingFixContinuations.timeOutAndAct`'s `ifNowEmpty` closure) without cancelling
/// the platform request, `abandonedGeneration(afterDrainAction:currentGeneration:)` records which
/// generation was abandoned. The next `didUpdateLocations` delivery that resolves no pending caller
/// consults `isGhostOfAbandonedRequest` to decide whether it is presumed to be that abandoned
/// request's belated answer (drop it) rather than a genuine significant-location-change/visit
/// callback (queue it as a `.periodic` hint, as before).
///
/// This is necessarily a heuristic, not a perfect disambiguation — CoreLocation gives no way to tag
/// a delivery with which API call produced it, which is the entire reason `PendingFixContinuations`
/// exists in the first place. At most one genuine hint is lost per abandoned generation (the first
/// unattributed delivery after an abandonment is always treated as the ghost); that is judged an
/// acceptable cost against mislabelling a `.locate`/`.manual`/`.geofence` capture as routine
/// `.periodic` (specs/001 §5.1, 001 §6.3).
struct StaleDeliveryPolicyTests {

    // MARK: - abandonedGeneration(afterDrainAction:currentGeneration:)

    @Test func abandonedGeneration_whenDrainDidNotStopTheManager_remembersTheCurrentGeneration() {
        // PresenceAccuracyPolicy chose .resetAccuracyToPresenceBaseline (presence active) — the
        // platform request was NOT cancelled, so it may still deliver later.
        #expect(StaleDeliveryPolicy.abandonedGeneration(afterDrainAction: .resetAccuracyToPresenceBaseline, currentGeneration: 3) == 3)
    }

    @Test func abandonedGeneration_whenDrainStoppedTheManager_isNil() {
        // PresenceAccuracyPolicy chose .stopUpdating (no presence session) — the platform request
        // WAS genuinely cancelled (manager.stopUpdatingLocation()); nothing will ever deliver for
        // it, so there is nothing to remember as abandoned.
        #expect(StaleDeliveryPolicy.abandonedGeneration(afterDrainAction: .stopUpdating, currentGeneration: 3) == nil)
    }

    // MARK: - isGhostOfAbandonedRequest(abandonedGeneration:currentGeneration:)

    @Test func isGhostOfAbandonedRequest_whenGenerationsMatch_isTrue() {
        // No fresh requestLocation() has been issued since the abandonment (currentGeneration
        // unchanged) — this unattributed delivery is presumed to be that abandoned request's
        // belated answer.
        #expect(StaleDeliveryPolicy.isGhostOfAbandonedRequest(abandonedGeneration: 3, currentGeneration: 3))
    }

    @Test func isGhostOfAbandonedRequest_whenAFreshRequestWasIssuedSince_isFalse() {
        // CoreLocation itself cancels a request when a new one is issued (Apple's documented
        // behavior) - once the generation has advanced, nothing can still be in flight for the OLD
        // generation, so an unattributed delivery can no longer be its ghost.
        #expect(!StaleDeliveryPolicy.isGhostOfAbandonedRequest(abandonedGeneration: 3, currentGeneration: 4))
    }

    @Test func isGhostOfAbandonedRequest_whenNothingWasAbandoned_isFalse() {
        #expect(!StaleDeliveryPolicy.isGhostOfAbandonedRequest(abandonedGeneration: nil, currentGeneration: 3))
    }

    // MARK: - abandonedGeneration(afterManagerStopped:) / abandonedGeneration(afterPlatformFailure:)
    //
    // specs/009-device-runtime.md §1.3's exception paragraph (I54 review): the abandonment MUST be
    // cleared whenever the outstanding request is otherwise resolved, so it can never outlive the
    // request that caused it. Two `SystemLocationProvider` paths resolve the outstanding request
    // without a delivery ever reaching `didUpdateLocations` (the only thing that previously cleared
    // the flag) — `stopPresence()` genuinely cancelling the manager, and `didFailWithError` on an
    // already-empty pending registry (a platform error IS the request's answer). Both must clear
    // unconditionally, regardless of what was previously remembered as abandoned.

    @Test func abandonedGeneration_afterManagerStopped_clearsEvenWhenSomethingWasAbandoned() {
        #expect(StaleDeliveryPolicy.abandonedGeneration(afterManagerStopped: 5) == nil)
    }

    @Test func abandonedGeneration_afterManagerStopped_staysNilWhenNothingWasAbandoned() {
        #expect(StaleDeliveryPolicy.abandonedGeneration(afterManagerStopped: nil) == nil)
    }

    @Test func abandonedGeneration_afterPlatformFailure_clearsEvenWhenSomethingWasAbandoned() {
        #expect(StaleDeliveryPolicy.abandonedGeneration(afterPlatformFailure: 5) == nil)
    }

    @Test func abandonedGeneration_afterPlatformFailure_staysNilWhenNothingWasAbandoned() {
        #expect(StaleDeliveryPolicy.abandonedGeneration(afterPlatformFailure: nil) == nil)
    }
}
