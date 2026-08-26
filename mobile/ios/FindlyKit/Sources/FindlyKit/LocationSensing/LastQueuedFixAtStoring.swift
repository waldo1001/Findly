import Foundation

/// specs/009-device-runtime.md §3.4 — "at least `syncIntervalMinutes × 0.8` has elapsed since the
/// last queued fix." Tracked as its own small store (rather than derived from `FixStoring`'s
/// contents) so `LocationSyncRunner` doesn't need to reach into `FixQueue` internals or parse
/// `recordedAt` timestamps back out of stored fixes — a plain, purpose-built timestamp. Not
/// required by specs/009 §2 to survive process death the way batch identity is (§3.4 doesn't say
/// so); the real device wiring still uses the `UserDefaults`-backed implementation below so a
/// significant-location-change relaunch (§3.4: "also relaunches the app after termination")
/// doesn't spuriously treat every relaunch as "never captured before".
public protocol LastQueuedFixAtStoring {
    func lastQueuedFixAt() -> Date?
    func recordQueuedFixAt(_ date: Date)

    /// I26 (specs/008-privacy-endpoints.md §4.4) — this store previously had NO clear capability
    /// at all, so its single timestamp survived both sign-out and account deletion. Wired into
    /// `LocationRuntimeContainer.wipeLocalState()`, the one consolidated local-wipe surface every
    /// sign-out/account-deletion path already funnels through — see that method's doc for why a
    /// new store joins the existing surface rather than a parallel wipe path.
    func clear()
}

public final class InMemoryLastQueuedFixAtStore: LastQueuedFixAtStoring {
    private var value: Date?

    public init(initial: Date? = nil) {
        self.value = initial
    }

    public func lastQueuedFixAt() -> Date? { value }
    public func recordQueuedFixAt(_ date: Date) { value = date }
    public func clear() { value = nil }
}

public final class UserDefaultsLastQueuedFixAtStore: LastQueuedFixAtStoring {
    private let defaults: UserDefaults
    private static let key = "FindlyKit.lastQueuedFixAt"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastQueuedFixAt() -> Date? {
        let seconds = defaults.double(forKey: Self.key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    public func recordQueuedFixAt(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
