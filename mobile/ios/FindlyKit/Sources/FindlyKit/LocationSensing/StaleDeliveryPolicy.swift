import Foundation

/// specs/009-device-runtime.md §1.1, specs/001-api-contract.md §5.1 `source` (I54 — I50 fix 8
/// regression, reported during I52's closing review and deliberately deferred to be done together
/// with I53: "once the provider is @MainActor the generation counter is far simpler to reason
/// about").
///
/// **The problem.** `PresenceAccuracyPolicy.drainAction` correctly stops
/// `SystemLocationProvider.applyDrainAction()` from calling `manager.stopUpdatingLocation()` when a
/// caller's own timeout drains the pending registry while the §1.3 presence session is active
/// (`.resetAccuracyToPresenceBaseline` instead of `.stopUpdating` — stopping would tear down
/// presence's own continuous stream, since both share one `CLLocationManager`). That correctly
/// protects presence, but as a side effect CoreLocation's `requestLocation()` is never actually
/// cancelled: it eventually delivers anyway, to an already-empty pending registry, and used to fall
/// straight through to the significant-location-change/visit "hint" path, mislabeled
/// `source: "periodic"` — even when a `.locate`/`.manual`/`.geofence` request is what actually
/// triggered the original capture. 001 §5.1's `source` is meant to say what triggered the capture,
/// and 001 §6.3 depends on `.locate` specifically being trustworthy.
///
/// **The fix.** `SystemLocationProvider` keeps a monotonic `requestGeneration`, bumped every time it
/// actually issues a fresh `requestLocation()` (`PendingFixContinuations.registerAndAct`'s `action`
/// closure — the seam that's already the single place a real platform request gets issued). When a
/// caller's own timeout drains the registry (`PendingFixContinuations.timeOutAndAct`'s `ifNowEmpty`
/// closure) without the drain action actually stopping the manager,
/// `abandonedGeneration(afterDrainAction:currentGeneration:)` says which generation to remember as
/// "abandoned, but CoreLocation might still answer it." The next `didUpdateLocations` delivery that
/// resolves no pending caller consults `isGhostOfAbandonedRequest` to decide whether it is presumed
/// to be that abandoned request's belated answer (drop it, never queue it) rather than a genuine
/// significant-location-change/visit callback (queue it as a `.periodic` hint, exactly as before).
///
/// **This is necessarily a heuristic, not a perfect disambiguation.** CoreLocation gives no way to
/// tag a delivery with which API call produced it — that ambiguity is the entire reason
/// `PendingFixContinuations` exists in the first place. At most one genuine
/// significant-location-change/visit hint is lost per abandoned generation (the first unattributed
/// delivery after an abandonment is always treated as the ghost, whether or not it actually is one);
/// `SystemLocationProvider` accepts that cost against mislabelling a `.locate`/`.manual`/`.geofence`
/// capture as routine `.periodic` (specs/001 §5.1, 001 §6.3) — the failure I54 exists to close.
///
/// **Deliberately plain state on `SystemLocationProvider`, not threaded through
/// `PendingFixContinuations`'s locked API (I53/I54 combined finding).** Every read/write of the
/// generation counter and the abandoned-generation flag happens from a method already isolated to
/// `SystemLocationProvider`'s own `@MainActor` — the registration point inside `awaitNextLocation`,
/// the timeout `Task`'s closure, and the `CLLocationManagerDelegate` callbacks. Before I53,
/// `SystemLocationProvider` was a plain class with no compiler-enforced isolation, which is exactly
/// why `PendingFixContinuations` needed its own lock: two genuinely concurrent callers on different
/// threads. A generation counter added to that same un-isolated class would have needed the same
/// lock-and-atomic-action discipline `registerAndAct`/`timeOutAndAct` already have — this is the
/// concrete sense in which I53's fix "simplifies" I54: with the class `@MainActor`, this bookkeeping
/// is just two private `var`s, mutated and read by already-serialized methods, no lock required.
public enum StaleDeliveryPolicy {
    /// `drainAction` is `PresenceAccuracyPolicy`'s own `ManagerAccuracyDrainAction` — reusing it
    /// (rather than a second boolean) keeps this decision anchored to the exact same "did we actually
    /// stop the manager" fact `applyDrainAction()` itself acts on, instead of a second, independently
    /// derived flag that could drift from it.
    public static func abandonedGeneration(afterDrainAction drainAction: ManagerAccuracyDrainAction, currentGeneration: Int) -> Int? {
        switch drainAction {
        case .stopUpdating:
            // The platform request WAS genuinely cancelled — nothing will ever deliver for it, so
            // there is nothing to remember as abandoned.
            return nil
        case .resetAccuracyToPresenceBaseline:
            // The platform request was NOT cancelled (presence is active) — it may still deliver
            // later, unattributed.
            return currentGeneration
        }
    }

    /// `abandonedGeneration` is `nil` whenever nothing is currently abandoned (never called with a
    /// stale reference to a previous, already-consumed one — see `SystemLocationProvider`'s call
    /// site, which clears it the moment it's used).
    public static func isGhostOfAbandonedRequest(abandonedGeneration: Int?, currentGeneration: Int) -> Bool {
        guard let abandonedGeneration else { return false }
        // CoreLocation itself cancels a request when a new one is issued (Apple's documented
        // behavior for requestLocation()) - once the generation has advanced past the one that was
        // abandoned, nothing can still be in flight for that OLD generation, so an unattributed
        // delivery can no longer be its ghost.
        return abandonedGeneration == currentGeneration
    }
}
