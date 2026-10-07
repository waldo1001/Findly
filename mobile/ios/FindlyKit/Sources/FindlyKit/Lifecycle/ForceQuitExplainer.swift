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
    var hasShownExplainer: Bool { get }
    func markExplainerShown()
    /// Removes both keys.
    func clear()
}

public final class InMemoryForceQuitExplainerStore: ForceQuitExplainerStoring {
    public private(set) var isTerminationFlagSet = false
    public private(set) var hasShownExplainer = false

    public init() {}

    public func setTerminationFlag() { isTerminationFlagSet = true }
    public func clearTerminationFlag() { isTerminationFlagSet = false }
    public func markExplainerShown() { hasShownExplainer = true }
    public func clear() {
        isTerminationFlagSet = false
        hasShownExplainer = false
    }
}

/// Plain `UserDefaults` (non-secret booleans), same shape as `UserDefaultsPermissionDisclosureStore`.
public final class UserDefaultsForceQuitExplainerStore: ForceQuitExplainerStoring {
    private static let flagKey = "com.findly.forceQuit.terminationFlag"
    private static let shownKey = "com.findly.forceQuit.explainerShown"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isTerminationFlagSet: Bool { defaults.bool(forKey: Self.flagKey) }
    public func setTerminationFlag() { defaults.set(true, forKey: Self.flagKey) }
    public func clearTerminationFlag() { defaults.removeObject(forKey: Self.flagKey) }
    public var hasShownExplainer: Bool { defaults.bool(forKey: Self.shownKey) }
    public func markExplainerShown() { defaults.set(true, forKey: Self.shownKey) }
    public func clear() {
        defaults.removeObject(forKey: Self.flagKey)
        defaults.removeObject(forKey: Self.shownKey)
    }
}

/// 011 §3 "Presentation" decision. Pure apart from the store it is handed.
public enum ForceQuitExplainerPresenter {
    /// Longest interval at which the presence session (009 §1.3) runs — i.e. at which a swipe-away
    /// actually silences the device.
    static let maxPresenceIntervalMinutes = 30

    /// Call once after launch resolution has landed on the Family Map (010 §1.1). Returns `true`
    /// when the explainer must be shown now: flag ∧ trackingEnabled ∧ interval ≤ 30 ∧ not yet
    /// shown. The flag is cleared in EVERY branch; `forceQuitExplainerShown` is recorded only when
    /// it is shown, so a silent clear never burns the one-time slot.
    ///
    /// `settings == nil` (no cached device settings) follows the runtime's own default — tracking on,
    /// 15 minutes — because that is the assumption the presence session itself runs under.
    @discardableResult
    public static func evaluate(store: ForceQuitExplainerStoring, settings: DeviceSettingsSnapshot?) -> Bool {
        guard store.isTerminationFlagSet else { return false }
        store.clearTerminationFlag()
        guard !store.hasShownExplainer else { return false }
        let tracking = settings?.trackingEnabled ?? true
        let interval = settings?.syncIntervalMinutes ?? 15
        guard tracking, interval <= maxPresenceIntervalMinutes else { return false }
        store.markExplainerShown()
        return true
    }
}
