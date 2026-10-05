import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59) — runs the refreshes `MapRefreshPolicy`
/// decides on: it owns the policy value, the cancellable 30 s timer task, and the call into the
/// screen's fetch. It contains no SwiftUI and no networking, so it is exercised end to end by
/// `MapRefreshDriverTests` under `swift test` (which compiles against AppKit — 004 §2.3).
///
/// **How the lifecycle wiring works.** A map screen forwards three SwiftUI signals and nothing else:
/// `appeared(phase:)` / `disappeared()` from its `.task` / `.onDisappear`, and
/// `scenePhaseChanged(_:)` from `.onChange(of: scenePhase)`. Each becomes a `MapRefreshPolicy.Event`;
/// the policy answers with "fetch for this reason" or "nothing", and `timerShouldRun` says whether the
/// 30 s timer may exist. The timer is a plain `Task` created when that flips true and cancelled when it
/// flips false, so the schedule is a pure function of "visible AND foregrounded" with no second source
/// of truth in the view.
///
/// Timing: the next 30 s wait starts when the previous tick's fetch has finished, so the period is
/// 30 s plus the request time and ticks can never pile up behind a slow request. A tick's fetch is not
/// tied to the timer task's cancellation: stopping the timer leaves a request already on the wire to
/// finish.
@MainActor
public final class MapRefreshDriver {
    /// §3.1/§3.6 — the same 30 s cadence the relative-time ticker already uses.
    public nonisolated static let defaultInterval: Duration = .seconds(30)

    /// Defaults through `Task.sleep(nanoseconds:)`, deliberately NOT `Task.sleep(for: Duration)` —
    /// see `SignInViewModel.sleep`'s doc (I13): the latter is a known Swift concurrency runtime
    /// defect (swiftlang/swift#86204) that crashes on exactly this `[weak self]` polling-loop shape.
    /// Cancellation is swallowed here and re-checked by the caller (`Task.isCancelled`), the same
    /// convention as `LocateViewModel`/`SignInViewModel`.
    public nonisolated static func liveSleep(_ duration: Duration) async {
        let (seconds, attoseconds) = duration.components
        let nanoseconds = UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds) / 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private var policy = MapRefreshPolicy()
    private let interval: Duration
    private let sleep: (Duration) async -> Void
    private let adopted: @MainActor () -> Void
    private let perform: @MainActor (MapRefreshPolicy.Trigger) async -> Void
    private var timerTask: Task<Void, Never>?

    /// `perform` runs ONE fetch for the given trigger and returns when it has finished — whatever the
    /// outcome; deciding what a failure means is the screen's view model's job (`failureOutcome`).
    /// It must read `inFlightTrigger`, not the trigger it was started with, to decide that after its
    /// `await`.
    ///
    /// `adopted` fires (synchronously, once) when an explicit Refresh/Retry arrives while an automatic
    /// fetch is already running (§3.6 "adopts a fetch already in flight"): no second request is made,
    /// the running one becomes the Refresh's own, and the screen shows its refreshing affordance now.
    public init(
        interval: Duration = MapRefreshDriver.defaultInterval,
        sleep: @escaping (Duration) async -> Void = MapRefreshDriver.liveSleep,
        adopted: @escaping @MainActor () -> Void = {},
        perform: @escaping @MainActor (MapRefreshPolicy.Trigger) async -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.adopted = adopted
        self.perform = perform
    }

    /// What the fetch currently in flight is for — `nil` when none is running. Starts as the trigger
    /// that began the fetch and is upgraded to `.explicit` if a Refresh adopts it, so an outcome
    /// handler that reads it after its `await` reports a failure as the Refresh's own.
    public var inFlightTrigger: MapRefreshPolicy.Trigger? { policy.inFlightTrigger }

    /// True exactly while a timer task exists (diagnostic/test seam — the policy's `timerShouldRun`
    /// is what decides it).
    public var isTimerRunning: Bool { timerTask != nil }

    /// The screen appeared (§3.6 #1, and #2's "navigation back to the map"). `phase` is the scene
    /// phase AT appearance, reported first so the policy never fetches a map that appeared while the
    /// app was not foregrounded. Returns when the fetch it started (if any) has finished.
    public func appeared(phase: MapRefreshPolicy.ScenePhase) async {
        await dispatch(.scenePhaseChanged(phase))
        await dispatch(.appeared)
    }

    /// The screen left the screen (navigated away). Stops the timer. The driver itself never cancels a
    /// fetch: a tick's fetch runs in its own unstructured task (see `syncTimer`), so stopping the timer
    /// leaves it to finish, as Android does. The one fetch that CAN be cancelled is the one a caller is
    /// awaiting — `appeared(phase:)`, `scenePhaseChanged(_:)`, `refresh()` — when that caller's own
    /// task is cancelled; for `.task { await appeared(...) }` that is the view going away, which is
    /// the point (nobody is left to see the first load).
    public func disappeared() {
        policy.handle(.disappeared)
        syncTimer()
    }

    /// §3.6 #2 — `.onChange(of: scenePhase)`. A return to `.active` while the map is visible fetches;
    /// leaving `.active` cancels the timer. Returns when the fetch it started (if any) has finished.
    public func scenePhaseChanged(_ phase: MapRefreshPolicy.ScenePhase) async {
        await dispatch(.scenePhaseChanged(phase))
    }

    /// The Refresh control / an error state's Retry. If a fetch is already in flight it makes no second
    /// request: it ADOPTS the running one (`adopted` fires, `inFlightTrigger` becomes `.explicit`) and
    /// returns at once; otherwise it returns when its own fetch has finished. Still runs after
    /// `end()` — a tap is not polling.
    public func refresh() async {
        await dispatch(.explicitRefresh)
    }

    /// A confirmed state change was reached (routed 404, expired/vanished group): ends POLLING — the
    /// timer stops and no automatic trigger fetches again. An explicit `refresh()` still runs.
    public func end() {
        policy.handle(.ended)
        syncTimer()
    }

    // MARK: - Private

    private func dispatch(_ event: MapRefreshPolicy.Event) async {
        let action = policy.handle(event)
        syncTimer()
        switch action {
        case .none:
            return
        case .adopt:
            adopted()
        case .fetch(let trigger):
            await perform(trigger)
            // Whatever `perform` did — including returning early because its task was cancelled —
            // the fetch is over; a stuck in-flight flag would silence every later trigger.
            policy.handle(.fetchFinished)
        }
    }

    private func timerTicked() async {
        await dispatch(.timerTick)
    }

    /// Makes the timer task exist iff the policy says it should. Idempotent.
    private func syncTimer() {
        if policy.timerShouldRun {
            guard timerTask == nil else { return }
            let interval = self.interval
            let sleep = self.sleep
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    await sleep(interval)
                    if Task.isCancelled { break }
                    // A strong reference only for the duration of one tick: while this task sleeps
                    // it holds nothing, so a discarded screen's driver (and view model) can go away.
                    guard let self else { break }
                    // The tick's fetch runs in its OWN unstructured task. Awaiting it here keeps the
                    // 30 s wait starting after the fetch ends, but `.value` does not propagate this
                    // task's cancellation — so stopping the timer (phase change, disappearance) never
                    // cancels a request already on the wire. A cancelled fetch an explicit Refresh had
                    // adopted would otherwise surface as that Refresh's failure (I59 review F5).
                    await Task { await self.timerTicked() }.value
                }
            }
        } else if let task = timerTask {
            task.cancel()
            timerTask = nil
        }
    }
}
