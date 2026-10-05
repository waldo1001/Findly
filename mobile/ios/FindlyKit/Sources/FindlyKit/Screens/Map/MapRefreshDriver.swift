import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59) — STUB for the red commit: the public
/// shape is final, every method is a no-op so `MapRefreshDriverTests` fails at runtime rather than
/// at compile time.
@MainActor
public final class MapRefreshDriver {
    public nonisolated static let defaultInterval: Duration = .seconds(30)

    public nonisolated static func liveSleep(_ duration: Duration) async {}

    public init(
        interval: Duration = MapRefreshDriver.defaultInterval,
        sleep: @escaping (Duration) async -> Void = MapRefreshDriver.liveSleep,
        perform: @escaping @MainActor (MapRefreshPolicy.Trigger) async -> Void
    ) {}

    public var isTimerRunning: Bool { false }

    public func appeared(phase: MapRefreshPolicy.ScenePhase) async {}
    public func disappeared() {}
    public func scenePhaseChanged(_ phase: MapRefreshPolicy.ScenePhase) async {}
    public func refresh() async {}
    public func end() {}
}
