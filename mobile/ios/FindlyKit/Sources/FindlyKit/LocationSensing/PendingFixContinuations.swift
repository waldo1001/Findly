import Foundation

/// specs/009-device-runtime.md §3.4 (I50 fix 5) — serializes access to the set of in-flight
/// `SystemLocationProvider.requestSingleFix` continuations. The single `pendingFixContinuation`
/// property this replaces silently overwrote (and therefore leaked — a `CheckedContinuation` that
/// never resumes is a permanent hung `Task`) whichever caller lost a race against a second
/// concurrent `requestSingleFix` call. I52's presence-session cadence timer and I51's
/// `LOCATE_REQUEST` handler both call `requestSingleFix` independently of each other and of the
/// opportunistic BG-refresh trigger, so concurrent calls are a realistic production scenario, not
/// a caller bug.
///
/// **A plain lock-protected class, not an actor.** `CLLocationManagerDelegate`'s callbacks
/// (`didUpdateLocations`/`didFailWithError`) are synchronous, non-`async` methods — routing every
/// one of them through an actor would force `SystemLocationProvider` to wrap each in an
/// unstructured `Task`, adding a suspension point between "CoreLocation answered" and "the
/// continuations actually resume" for no benefit (there is no other work these methods need to
/// interleave with). A lock keeps registration and resume symmetric and immediate.
///
/// CoreLocation-free by design (only `LocationFix`/`FixSource`/`Foundation`), so it's testable on
/// any host — unlike `SystemLocationProvider` itself, which is `#if os(iOS) &&
/// canImport(CoreLocation)` platform glue `swift test` cannot exercise.
public final class PendingFixContinuations: @unchecked Sendable {
    public typealias ID = UUID

    private let lock = NSLock()
    private var pending: [ID: (source: FixSource, continuation: CheckedContinuation<LocationFix, Error>)] = [:]

    public init() {}

    /// Registers `continuation` under a fresh id for `source`. `needsPlatformRequest` tells the
    /// caller whether it must actually call `CLLocationManager.requestLocation()` (CoreLocation
    /// permits only one in-flight request at a time; a caller riding along on an already-in-flight
    /// request is resumed by the same eventual platform callback via `resumeAll`, at no extra GPS
    /// cost).
    ///
    /// **Tier-aware, not just `pending.isEmpty` (I50 fix 1, Blocking).** The registry used to treat
    /// "is anything else pending" as the only question, which meant a `.locate` (high-accuracy)
    /// caller joining an in-flight `.periodic` (balanced-accuracy) request never got its own
    /// `requestLocation()` re-issue — it rode along and was eventually resumed with the balanced
    /// fix, mistagged `source: "locate"` (specs/009 §1.1's accuracy table, specs/001 §6.3's locate
    /// fulfil). `needsPlatformRequest` is now `true` whenever `source`'s tier is STRICTLY HIGHER
    /// than every tier already pending — i.e. this caller's accuracy need is not already being
    /// satisfied by what's in flight — and `false` otherwise (an equal-or-lower-tier joiner rides
    /// along exactly as before; a balanced caller receiving a high-accuracy fix costs nothing
    /// extra). `SystemLocationProvider.awaitNextLocation` uses this same signal to decide whether to
    /// raise `desiredAccuracy` (I50 fix 2) — see that call site's doc.
    @discardableResult
    public func register(source: FixSource, continuation: CheckedContinuation<LocationFix, Error>) -> (id: ID, needsPlatformRequest: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let newTier = FixAccuracyPolicy.tier(for: source)
        let highestPendingTier = pending.values.map { FixAccuracyPolicy.tier(for: $0.source) }.max()
        let needsPlatformRequest = highestPendingTier.map { newTier > $0 } ?? true
        let id = ID()
        pending[id] = (source, continuation)
        return (id, needsPlatformRequest)
    }

    /// Atomic counterpart to `register` (I50 review 2nd round, Major). `register` correctly
    /// reports `needsPlatformRequest`, but if the CALLER acts on that report (writing
    /// `manager.desiredAccuracy` and calling `manager.requestLocation()`) only AFTER this method
    /// returns — i.e. after the lock is released — nothing stops a second, genuinely concurrent
    /// `register`/act pair on another thread from interleaving with it: whichever caller's
    /// CoreLocation mutation lands last on the manager silently wins, independent of which
    /// caller's tier was actually higher (Apple documents that a new `requestLocation()` cancels
    /// the previous one). I52's presence timer, I51's push handler, and the background-refresh
    /// trigger are three realistic concurrent callers with no shared actor/thread guarantee, so
    /// this is not a theoretical race.
    ///
    /// `registerAndAct` closes the gap by running `action` (supplied by
    /// `SystemLocationProvider.awaitNextLocation`) WHILE STILL HOLDING the lock, exactly when
    /// `needsPlatformRequest` is true — so this registration's "am I the one that must act" decision
    /// and the act itself are one indivisible step, and can never interleave with another
    /// registration's (or `timeOutAndAct`'s) own act. `continuation` is stored but never resumed
    /// here — resumption always happens outside the lock, via `resumeAll`/`failAll`/`timeOutAndAct`,
    /// exactly as `register` already guaranteed.
    @discardableResult
    public func registerAndAct(source: FixSource, continuation: CheckedContinuation<LocationFix, Error>, ifNeedsPlatformRequest action: () -> Void) -> ID {
        lock.lock()
        defer { lock.unlock() }
        let newTier = FixAccuracyPolicy.tier(for: source)
        let highestPendingTier = pending.values.map { FixAccuracyPolicy.tier(for: $0.source) }.max()
        let needsPlatformRequest = highestPendingTier.map { newTier > $0 } ?? true
        let id = ID()
        pending[id] = (source, continuation)
        if needsPlatformRequest {
            action()
        }
        return id
    }

    /// A single caller's own timeout (specs/009 §1.1: "no fix is better than a burned battery") —
    /// resumes and removes ONLY this id, leaving every other concurrently-pending caller untouched
    /// so it can still be satisfied by the real platform answer (or its own, independent timeout).
    /// A no-op if `id` already resumed via `resumeAll`/`failAll`/an earlier `timeOut` call — the
    /// exact race a leaked/double-resumed continuation used to hit.
    ///
    /// Returns whether THIS call is what just emptied the registry (I50 fix 8, Minor) — `true` only
    /// when `id` was actually still pending and removing it left nothing behind. Nothing previously
    /// cancelled CoreLocation's still in-flight `requestLocation()` once every caller gave up, so
    /// the eventual delivery fell through to `SystemLocationProvider`'s significant-location-change
    /// hint path mislabeled `source: "periodic"` regardless of what had actually triggered the
    /// request. `SystemLocationProvider.awaitNextLocation` uses `true` here as the signal to call
    /// `manager.stopUpdatingLocation()` (CoreLocation's documented way to cancel a `requestLocation()`
    /// in flight) — never on a no-op call (already resumed, or another caller is still waiting), so
    /// a still-live request is never torn out from under a still-pending sibling.
    @discardableResult
    public func timeOut(id: ID, error: Error) -> Bool {
        lock.lock()
        let entry = pending.removeValue(forKey: id)
        let isNowEmpty = entry != nil && pending.isEmpty
        lock.unlock()
        entry?.continuation.resume(throwing: error)
        return isNowEmpty
    }

    /// Atomic counterpart to `timeOut` (I50 review 2nd round, Major) — the second face of the same
    /// gap `registerAndAct` closes. `timeOut` correctly reports whether THIS timeout is the one
    /// that emptied the registry, but if the caller's `manager.stopUpdatingLocation()` runs only
    /// AFTER this method returns, nothing stops a brand-new caller's `registerAndAct` (on another
    /// thread) from registering and re-issuing `requestLocation()` in the gap between "registry
    /// went empty" and "stop the old request" — so the belated stop can cancel a live request that,
    /// by the time it actually runs, legitimately belongs to a new, still-pending caller.
    ///
    /// Runs `action` WHILE STILL HOLDING the lock, exactly when `id`'s removal is what emptied the
    /// registry, so this decision-and-act is indivisible with respect to every `registerAndAct`
    /// (and every other `timeOutAndAct`) call, which share the same lock. `continuation.resume`
    /// still happens AFTER the lock is released, matching every other resume in this type — never
    /// hold the lock across a continuation resume.
    @discardableResult
    public func timeOutAndAct(id: ID, error: Error, ifNowEmpty action: () -> Void) -> Bool {
        lock.lock()
        let entry = pending.removeValue(forKey: id)
        let isNowEmpty = entry != nil && pending.isEmpty
        if isNowEmpty {
            action()
        }
        lock.unlock()
        entry?.continuation.resume(throwing: error)
        return isNowEmpty
    }

    /// CoreLocation delivered one location for however many callers are currently waiting on the
    /// single in-flight `requestLocation()` — resumes EVERY pending continuation, each with a
    /// `LocationFix` tagged with ITS OWN `source` (`makeFix` is
    /// `CLLocation.toLocationFix(source:)`, injected so this type stays CoreLocation-free), then
    /// clears the registry. Returns whether anything was actually resumed, so
    /// `SystemLocationProvider`'s delegate callback can fall through to its significant-location-
    /// change/visit-monitoring hint path exactly when this was a stray delivery with nobody
    /// waiting.
    @discardableResult
    public func resumeAll(makeFix: (FixSource) -> LocationFix) -> Bool {
        lock.lock()
        let all = pending
        pending.removeAll()
        lock.unlock()
        guard !all.isEmpty else { return false }
        for entry in all.values {
            entry.continuation.resume(returning: makeFix(entry.source))
        }
        return true
    }

    /// CoreLocation itself failed — resumes and removes every pending continuation with the same
    /// error (mirrors `resumeAll`'s "one platform answer, every caller" shape; specs/009 §9: the
    /// error carries only a safe category, never coordinates/deviceId).
    public func failAll(with error: Error) {
        lock.lock()
        let all = pending
        pending.removeAll()
        lock.unlock()
        for entry in all.values {
            entry.continuation.resume(throwing: error)
        }
    }

    /// Test/introspection only — production code never needs to know how many callers are
    /// pending, only whether ITS OWN id still is (`timeOut`) or whether ANY are (`resumeAll`'s
    /// return value).
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }
}
