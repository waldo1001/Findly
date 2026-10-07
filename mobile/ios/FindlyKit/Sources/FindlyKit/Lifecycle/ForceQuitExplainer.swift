import Foundation

/// specs/011-device-lifecycle-and-staleness.md §3 (I62) — the one-time iOS "you swiped Findly away"
/// explainer. Copy is verbatim from the spec.
public enum ForceQuitExplainer {
    public static let title = "Keep Findly open in the background"
    public static let body = "Swiping Findly away stops sharing your location until you open it again. To keep sharing, leave Findly in the app switcher — it uses very little battery."
    public static let actionTitle = "Got it"
}

/// The two local keys of 011 §3: the termination flag (written by `applicationWillTerminate`, which
/// MUST only write it — no network, a few seconds) and `forceQuitExplainerShown`. Both are cleared
/// by the end-of-session wipe (`LocationRuntimeContainer.wipeLocalState()`, 009 §9 / I43).
public protocol ForceQuitExplainerStoring: AnyObject {
    var isTerminationFlagSet: Bool { get }
    func setTerminationFlag()
    func clearTerminationFlag()
    /// "The explainer is due": the decision was made (flag consumed) but the user has not yet
    /// acknowledged it, so a dropped/interrupted presentation retries.
    var isExplainerDue: Bool { get }
    func setExplainerDue()
    func clearExplainerDue()
    var hasShownExplainer: Bool { get }
    func markExplainerShown()
    /// Removes both keys.
    func clear()
}

public final class InMemoryForceQuitExplainerStore: ForceQuitExplainerStoring {
    public private(set) var isTerminationFlagSet = false
    public private(set) var hasShownExplainer = false
    public private(set) var isExplainerDue = false

    public init() {}

    public func setExplainerDue() { isExplainerDue = true }
    public func clearExplainerDue() { isExplainerDue = false }

    public func setTerminationFlag() { isTerminationFlagSet = true }
    public func clearTerminationFlag() { isTerminationFlagSet = false }
    public func markExplainerShown() { hasShownExplainer = true }
    public func clear() {
        isTerminationFlagSet = false
        isExplainerDue = false
        hasShownExplainer = false
    }
}

/// Plain `UserDefaults` (non-secret booleans), same shape as `UserDefaultsPermissionDisclosureStore`.
public final class UserDefaultsForceQuitExplainerStore: ForceQuitExplainerStoring {
    private static let flagKey = "com.findly.forceQuit.terminationFlag"
    private static let dueKey = "com.findly.forceQuit.explainerDue"
    private static let shownKey = "com.findly.forceQuit.explainerShown"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isTerminationFlagSet: Bool { defaults.bool(forKey: Self.flagKey) }
    public func setTerminationFlag() { defaults.set(true, forKey: Self.flagKey) }
    public func clearTerminationFlag() { defaults.removeObject(forKey: Self.flagKey) }
    public var isExplainerDue: Bool { defaults.bool(forKey: Self.dueKey) }
    public func setExplainerDue() { defaults.set(true, forKey: Self.dueKey) }
    public func clearExplainerDue() { defaults.removeObject(forKey: Self.dueKey) }
    public var hasShownExplainer: Bool { defaults.bool(forKey: Self.shownKey) }
    public func markExplainerShown() { defaults.set(true, forKey: Self.shownKey) }
    public func clear() {
        defaults.removeObject(forKey: Self.flagKey)
        defaults.removeObject(forKey: Self.dueKey)
        defaults.removeObject(forKey: Self.shownKey)
    }
}

/// 011 §3 "Presentation" decision. Pure apart from the store it is handed.
public enum ForceQuitExplainerPresenter {
    /// Longest interval at which the presence session (009 §1.3) runs — i.e. at which a swipe-away
    /// actually silences the device.
    static let maxPresenceIntervalMinutes = 30

    /// Call whenever the Family Map appears (010 §1.1). The termination flag is consumed and cleared
    /// in EVERY branch (011 §3); when flag ∧ trackingEnabled ∧ interval ≤ 30 ∧ not yet shown, the
    /// explainer becomes persistently "due". Returns `true` while it is due, so a presentation that
    /// never reached the screen (a sheet or cover was on top) is retried at the next appearance.
    /// `forceQuitExplainerShown` is recorded only by `acknowledge(store:)` — the user tapping "Got it".
    ///
    /// `settings == nil` (no cached device settings) follows the runtime's own default — tracking on,
    /// 15 minutes — because that is the assumption the presence session itself runs under.
    @discardableResult
    public static func evaluate(store: ForceQuitExplainerStoring, settings: DeviceSettingsSnapshot?) -> Bool {
        if store.isTerminationFlagSet {
            store.clearTerminationFlag()
            let tracking = settings?.trackingEnabled ?? true
            let interval = settings?.syncIntervalMinutes ?? 15
            if !store.hasShownExplainer, tracking, interval <= maxPresenceIntervalMinutes {
                store.setExplainerDue()
            }
        }
        if store.hasShownExplainer { store.clearExplainerDue() }
        return store.isExplainerDue
    }

    /// The user tapped "Got it": record the one-time slot as used and drop the due state.
    public static func acknowledge(store: ForceQuitExplainerStoring) {
        store.markExplainerShown()
        store.clearExplainerDue()
    }
}
