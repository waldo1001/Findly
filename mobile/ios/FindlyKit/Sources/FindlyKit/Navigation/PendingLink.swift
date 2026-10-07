import Foundation

/// specs/010-app-shell-and-screen-ux.md §1.3 (H20 / 000 §D20, row I63) — the pending link: a
/// join/invite link that arrived while the app could not act on it yet (signed out, launch
/// resolution unfinished, or — I64 — the app-lock screen showing). One slot, kept in memory AND
/// `UserDefaults`, valid for 1 hour, replayed once after launch resolution.

public enum PendingLinkKind: String, Codable, Equatable, Sendable {
    case familyInvite
    case groupJoin
}

public struct PendingLink: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let kind: PendingLinkKind
    /// Canonical 8-char code (already whitelist-normalized by the 007 parsers).
    public let code: String
    public let receivedAt: Date

    public init(kind: PendingLinkKind, code: String, receivedAt: Date) {
        self.kind = kind
        self.code = code
        self.receivedAt = receivedAt
    }

    /// specs/010 §1.3 — the value MUST NOT be logged; interpolating or dumping a `PendingLink`
    /// therefore never reveals the code.
    public var description: String { "PendingLink(kind: \(kind.rawValue), code: <redacted>)" }
    public var debugDescription: String { description }
}

/// What the app can do with a link right now. `isLocked` is the seam for the I64 app lock.
public struct LinkActState: Equatable, Sendable {
    public var isSignedIn: Bool
    public var isLaunchResolved: Bool
    public var isLocked: Bool

    public init(isSignedIn: Bool, isLaunchResolved: Bool, isLocked: Bool) {
        self.isSignedIn = isSignedIn
        self.isLaunchResolved = isLaunchResolved
        self.isLocked = isLocked
    }

    public var canAct: Bool { isSignedIn && isLaunchResolved && !isLocked }
}

public enum LinkCaptureDecision: Equatable, Sendable {
    case navigateNow
    case store
}

public enum PendingReplayDecision: Equatable, Sendable {
    case replay(PendingLink)
    case discard
    case wait
}

/// Pure decisions (010 §1.3, last bullet) — no I/O, no clock of its own.
public enum PendingLinkPolicy {
    /// 010 §1.3 "valid for 1 hour from `receivedAt`".
    public static let validity: TimeInterval = 3600

    public static func captureDecision(_ state: LinkActState) -> LinkCaptureDecision {
        state.canAct ? .navigateNow : .store
    }

    /// Expired (age >= 1 h) is discarded regardless of app state. A `receivedAt` in the future
    /// (clock moved backwards) cannot be aged reliably and is discarded too, so a stored link can
    /// never outlive its hour.
    public static func replayDecision(pending: PendingLink?, now: Date, state: LinkActState) -> PendingReplayDecision {
        guard let pending else { return .wait }
        let age = now.timeIntervalSince(pending.receivedAt)
        if age < 0 || age >= validity { return .discard }
        return state.canAct ? .replay(pending) : .wait
    }
}

public protocol PendingLinkStoring: AnyObject {
    func load() -> PendingLink?
    func save(_ link: PendingLink)
    func clear()
}

public final class InMemoryPendingLinkStore: PendingLinkStoring {
    private var link: PendingLink?
    public init() {}
    public func load() -> PendingLink? { link }
    public func save(_ link: PendingLink) { self.link = link }
    public func clear() { link = nil }
}

/// App-private `UserDefaults` (010 §1.3 "Persistence": no Keychain requirement — the code is a value
/// the user already holds in their messenger). Never logged.
public final class UserDefaultsPendingLinkStore: PendingLinkStoring {
    static let key = "com.findly.pendingLink"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PendingLink? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        guard let link = try? JSONDecoder().decode(PendingLink.self, from: data) else {
            defaults.removeObject(forKey: Self.key)
            return nil
        }
        return link
    }

    public func save(_ link: PendingLink) {
        guard let data = try? JSONEncoder().encode(link) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// The single pending-link slot: memory in front of a `PendingLinkStoring`.
@MainActor
public final class PendingLinkSlot {
    private let store: PendingLinkStoring
    public let now: () -> Date
    private var memory: PendingLink?

    public init(store: PendingLinkStoring, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// One slot only — a newer link replaces an older one.
    public func put(_ link: PendingLink) {
        memory = link
        store.save(link)
    }

    /// Consumes the link when it is valid and the app can act: clears the slot FIRST, then returns
    /// it. An expired link is discarded silently. Otherwise leaves the slot untouched.
    public func take(_ state: LinkActState) -> PendingLink? {
        let pending = memory ?? store.load()
        switch PendingLinkPolicy.replayDecision(pending: pending, now: now(), state: state) {
        case .replay(let link):
            clear()
            return link
        case .discard:
            clear()
            return nil
        case .wait:
            return nil
        }
    }

    /// Replay, expiry and the end-of-session wipe (`EndOfSessionRoutine`) all land here.
    public func clear() {
        memory = nil
        store.clear()
    }
}
