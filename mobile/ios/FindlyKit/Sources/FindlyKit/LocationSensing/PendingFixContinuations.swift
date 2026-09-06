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

    /// Registers `continuation` under a fresh id for `source`. `isFirst` tells the caller whether
    /// this registration is the ONLY thing currently waiting — i.e. whether it must actually call
    /// `CLLocationManager.requestLocation()` (CoreLocation permits only one in-flight request at a
    /// time; a caller joining an already-in-flight request rides along and is resumed by the same
    /// eventual platform callback via `resumeAll`, at no extra GPS cost).
    @discardableResult
    public func register(source: FixSource, continuation: CheckedContinuation<LocationFix, Error>) -> (id: ID, isFirst: Bool) {
        lock.lock()
        defer { lock.unlock() }
        let isFirst = pending.isEmpty
        let id = ID()
        pending[id] = (source, continuation)
        return (id, isFirst)
    }

    /// A single caller's own timeout (specs/009 §1.1: "no fix is better than a burned battery") —
    /// resumes and removes ONLY this id, leaving every other concurrently-pending caller untouched
    /// so it can still be satisfied by the real platform answer (or its own, independent timeout).
    /// A no-op if `id` already resumed via `resumeAll`/`failAll`/an earlier `timeOut` call — the
    /// exact race a leaked/double-resumed continuation used to hit.
    public func timeOut(id: ID, error: Error) {
        lock.lock()
        let entry = pending.removeValue(forKey: id)
        lock.unlock()
        entry?.continuation.resume(throwing: error)
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
