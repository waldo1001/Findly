import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59) — STUB for the red commit: the public
/// shape is final, every decision is deliberately wrong so the tests in `MapRefreshPolicyTests`
/// fail at runtime rather than at compile time.
public struct MapRefreshPolicy: Equatable, Sendable {
    public enum ScenePhase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    public enum Trigger: Equatable, Sendable {
        case firstAppearance
        case returnToMap
        case foregroundReturn
        case periodic
        case explicit
    }

    public enum Event: Equatable, Sendable {
        case appeared
        case disappeared
        case scenePhaseChanged(ScenePhase)
        case timerTick
        case explicitRefresh
        case fetchFinished
        case ended
    }

    public enum Action: Equatable, Sendable {
        case none
        case fetch(Trigger)
    }

    public enum FailureOutcome: Equatable, Sendable {
        case keepLastData
        case showError
    }

    public private(set) var isVisible = false
    public private(set) var phase: ScenePhase = .active
    public private(set) var isFetching = false
    public private(set) var isEnded = false

    public init() {}

    public var timerShouldRun: Bool { false }

    @discardableResult
    public mutating func handle(_ event: Event) -> Action {
        .none
    }

    public static func failureOutcome(for trigger: Trigger, hasDataOnScreen: Bool) -> FailureOutcome {
        .keepLastData
    }
}
