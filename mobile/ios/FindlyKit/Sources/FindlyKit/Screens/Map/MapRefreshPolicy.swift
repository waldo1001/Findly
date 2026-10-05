import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59) — WHEN the family map (and the §3.2
/// group map) re-fetches its positions, as pure state: no SwiftUI, no timers, no network.
///
/// **The problem this exists to prevent.** The map loaded its roster once, in the view's `.task`
/// (first appearance), and afterwards only on the Refresh control, so a person reopening the app
/// after an hour saw the positions from the last load while the server held fresher ones. §3.6 makes
/// the map refresh on first appearance, on every return to the foreground and to the map, and every
/// 30 s while it is on screen AND the app is foregrounded — never in the background.
///
/// This type owns the *decisions*; `MapRefreshDriver` owns the timer task and runs the fetches the
/// decisions ask for; the screens only forward SwiftUI lifecycle signals. That split is what lets the
/// rules below be unit-tested under `swift test` (which compiles against AppKit, not UIKit — 004 §2.3)
/// instead of being buried in view modifiers no test can observe.
///
/// The rules, each pinned by a test in `MapRefreshPolicyTests`:
/// - **Visible AND foregrounded** (`timerShouldRun`) is the only state in which the 30 s timer may
///   run. `.inactive` counts as NOT foregrounded: the app is covered (app switcher, notification
///   centre, a system dialog) and cannot show a fresh position to anyone.
/// - **Any return to `.active` while visible fetches** (`.foregroundReturn`), whether it came from
///   `.background` or `.inactive` — the timer was stopped in between, so the data may be stale, and
///   one extra small `GET` on a system-dialog blip is cheaper than reasoning about which blips are
///   long enough to matter.
/// - **At most one fetch in flight.** A trigger that arrives while one is running is DROPPED, not
///   queued: `fetchFinished` never starts anything.
/// - **A stale tick is ignored.** The timer task is cancelled the moment the phase changes, but a
///   tick that was already delivered must still not become a request.
/// - **`ended`** (a routed 404 / an expired group) stops everything — there is nothing left to refresh.
public struct MapRefreshPolicy: Equatable, Sendable {
    /// Mirrors SwiftUI's `ScenePhase` without importing it, so this stays a plain value type. The
    /// SwiftUI → this mapping is `init(_:)` in `MapRefreshScenePhase+SwiftUI.swift`.
    public enum ScenePhase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    /// WHY a fetch was started. Decides only how a *failure* is treated (`failureOutcome`); the fetch
    /// itself is identical for every trigger.
    public enum Trigger: Equatable, Sendable {
        /// §3.6 #1 — the screen's first appearance.
        case firstAppearance
        /// §3.6 #2 — navigation back to the map from another screen (the map re-appeared).
        case returnToMap
        /// §3.6 #2 — the app returned to the foreground while the map is the visible screen.
        case foregroundReturn
        /// §3.6 #3 — the 30 s timer.
        case periodic
        /// The Refresh control or an error state's Retry — a user action that reports its own failure.
        case explicit
    }

    public enum Event: Equatable, Sendable {
        case appeared
        case disappeared
        case scenePhaseChanged(ScenePhase)
        case timerTick
        case explicitRefresh
        /// The fetch the policy asked for has ended (success, failure or cancellation alike).
        case fetchFinished
        /// A terminal state was reached (routed 404, expired group): nothing is left to refresh.
        case ended
    }

    public enum Action: Equatable, Sendable {
        case none
        case fetch(Trigger)
    }

    public enum FailureOutcome: Equatable, Sendable {
        /// The last data stays on screen; no error surface.
        case keepLastData
        /// The error state replaces the content (001's `ErrorStateView` retry rendering, 010 §9).
        case showError
    }

    public private(set) var isVisible = false
    /// Assumed `.active` until told otherwise: SwiftUI's `onChange(of: scenePhase)` does not fire for
    /// the value a view starts with, and a screen that is being built is by definition on screen.
    public private(set) var phase: ScenePhase = .active
    public private(set) var isFetching = false
    public private(set) var isEnded = false
    private var hasAppeared = false

    public init() {}

    /// §3.6 #3 — the 30 s timer exists exactly while this is true.
    public var timerShouldRun: Bool {
        isVisible && phase == .active && !isEnded
    }

    @discardableResult
    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .appeared:
            guard !isVisible else { return .none }
            isVisible = true
            let trigger: Trigger = hasAppeared ? .returnToMap : .firstAppearance
            hasAppeared = true
            // Appearing while not foregrounded: nothing is fetched now; the return to `.active`
            // fetches (§3.6: never in the background).
            guard phase == .active else { return .none }
            return beginFetch(trigger)

        case .disappeared:
            isVisible = false
            return .none

        case .scenePhaseChanged(let newPhase):
            let oldPhase = phase
            phase = newPhase
            guard isVisible, oldPhase != .active, newPhase == .active else { return .none }
            return beginFetch(.foregroundReturn)

        case .timerTick:
            guard timerShouldRun else { return .none }
            return beginFetch(.periodic)

        case .explicitRefresh:
            return beginFetch(.explicit)

        case .fetchFinished:
            isFetching = false
            return .none

        case .ended:
            isEnded = true
            return .none
        }
    }

    /// §3.6: "at most one request in flight (a trigger arriving while one is running is dropped, not
    /// queued)". Starting a fetch IS the act of marking one in flight — there is no separate "fetch
    /// started" event to forget to send.
    private mutating func beginFetch(_ trigger: Trigger) -> Action {
        guard !isEnded, !isFetching else { return .none }
        isFetching = true
        return .fetch(trigger)
    }

    /// §3.6: "a periodic or foreground refresh that fails keeps the last data on screen with no error
    /// surface — only a *first* load failure shows the error state, and an explicit Refresh still
    /// reports its own failure."
    ///
    /// Keyed on whether there is data to keep, NOT on the trigger's name: a first load that had to
    /// wait for the foreground (the screen appeared while backgrounded) is still a first load and
    /// must report its failure, and a map stuck on its first-load error state must stay on it when a
    /// later periodic attempt also fails.
    public static func failureOutcome(for trigger: Trigger, hasDataOnScreen: Bool) -> FailureOutcome {
        if trigger == .explicit { return .showError }
        return hasDataOnScreen ? .keepLastData : .showError
    }
}
