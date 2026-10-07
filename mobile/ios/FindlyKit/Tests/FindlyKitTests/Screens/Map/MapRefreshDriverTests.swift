import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59), §10 "Data freshness" — the lifecycle
/// half of the refresh trigger: the cancellable 30 s timer task that exists ONLY while the map is
/// visible and the app is foregrounded, and the single-fetch-in-flight rule as it actually plays out
/// across async calls. `MapRefreshPolicyTests` pins the decisions; these pin that the driver acts on
/// them — in particular that a stopped timer really stops (the failure mode the policy tests cannot
/// see), driven by `ManualSleeper` so no test waits on a wall clock.
@MainActor
struct MapRefreshDriverTests {

    @MainActor private struct Fixture {
        let sleeper = ManualSleeper()
        let recorder = RefreshRecorder()
        let driver: MapRefreshDriver

        init() {
            let sleeper = self.sleeper
            let recorder = self.recorder
            let driver = MapRefreshDriver(
                sleep: { await sleeper.sleep($0) },
                adopted: { recorder.adopted() },
                perform: { await recorder.perform($0) }
            )
            recorder.readEffectiveTrigger = { [unowned driver] in driver.inFlightTrigger }
            self.driver = driver
        }
    }

    /// Lets a timer that should NOT fire have every chance to — a negative assertion needs a window.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 60_000_000)
    }

    // MARK: - §3.6 #1 first appearance, #3 the 30 s timer

    @Test func appearing_whileForegrounded_fetchesOnce_andStartsTheTimer() async throws {
        let f = Fixture()

        await f.driver.appeared(phase: .active)

        #expect(f.recorder.triggers == [.firstAppearance])
        #expect(f.driver.isTimerRunning)
        try await waitUntil { f.sleeper.parkedCount == 1 }
    }

    @Test func theTimerSleepsForTheThirtySecondInterval() async throws {
        let f = Fixture()

        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }

        #expect(f.sleeper.requestedDurations == [.seconds(30)])
        #expect(MapRefreshDriver.defaultInterval == .seconds(30))
    }

    @Test func eachTimerTick_fetchesPeriodically() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }

        f.sleeper.fire()
        try await waitUntil { f.recorder.triggers == [.firstAppearance, .periodic] }
        // The loop re-arms itself after the tick's fetch completes.
        try await waitUntil { f.sleeper.parkedCount == 1 }
        f.sleeper.fire()
        try await waitUntil { f.recorder.triggers == [.firstAppearance, .periodic, .periodic] }
    }

    // MARK: - §3.6: no polling in the background, ever

    @Test(arguments: [MapRefreshPolicy.ScenePhase.inactive, MapRefreshPolicy.ScenePhase.background])
    func leavingTheForeground_cancelsTheTimer_soNothingFetchesWhenTimeWouldHavePassed(_ phase: MapRefreshPolicy.ScenePhase) async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }

        await f.driver.scenePhaseChanged(phase)

        #expect(f.driver.isTimerRunning == false)
        try await waitUntil { f.sleeper.parkedCount == 0 }
        f.sleeper.fire()
        try await settle()
        #expect(f.recorder.triggers == [.firstAppearance], "no tick may become a request while not foregrounded")
    }

    @Test func appearing_whileBackgrounded_neitherFetchesNorStartsATimer() async throws {
        let f = Fixture()

        await f.driver.appeared(phase: .background)
        try await settle()

        #expect(f.recorder.triggers.isEmpty)
        #expect(f.driver.isTimerRunning == false)
        #expect(f.sleeper.requestedDurations.isEmpty)
    }

    @Test func appearingWhileBackgrounded_thenReturningToTheForeground_fetchesAndStartsTheTimer() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .background)

        await f.driver.scenePhaseChanged(.active)

        #expect(f.recorder.triggers == [.foregroundReturn])
        #expect(f.driver.isTimerRunning)
        try await waitUntil { f.sleeper.parkedCount == 1 }
    }

    // MARK: - §3.6 #2 every return to the foreground — and exactly ONE timer afterwards

    @Test func returningToTheForeground_fetchesAndRestartsExactlyOneTimer() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }
        await f.driver.scenePhaseChanged(.inactive)
        await f.driver.scenePhaseChanged(.background)
        try await waitUntil { f.sleeper.parkedCount == 0 }

        await f.driver.scenePhaseChanged(.inactive)
        await f.driver.scenePhaseChanged(.active)

        #expect(f.recorder.triggers == [.firstAppearance, .foregroundReturn])
        try await waitUntil { f.sleeper.parkedCount == 1 }

        f.sleeper.fire()
        try await waitUntil { f.recorder.triggers.count == 3 }
        try await settle()
        #expect(f.recorder.triggers == [.firstAppearance, .foregroundReturn, .periodic], "one tick per interval — a leaked second timer would have fetched twice")
    }

    @Test func navigatingBackToTheMap_fetchesAgain() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        f.driver.disappeared()

        await f.driver.appeared(phase: .active)

        #expect(f.recorder.triggers == [.firstAppearance, .returnToMap])
        #expect(f.driver.isTimerRunning)
    }

    // MARK: - §3.6: the timer stops when the map leaves the screen

    @Test func disappearing_cancelsTheTimer() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }

        f.driver.disappeared()

        #expect(f.driver.isTimerRunning == false)
        try await waitUntil { f.sleeper.parkedCount == 0 }
        f.sleeper.fire()
        try await settle()
        #expect(f.recorder.triggers == [.firstAppearance])
    }

    @Test func returningToTheForeground_afterTheMapLeftTheScreen_doesNotFetchOrRestartTheTimer() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        f.driver.disappeared()
        await f.driver.scenePhaseChanged(.background)

        await f.driver.scenePhaseChanged(.active)

        #expect(f.recorder.triggers == [.firstAppearance])
        #expect(f.driver.isTimerRunning == false)
    }

    // MARK: - §3.6: at most one request in flight — dropped, not queued

    @Test func aTrigger_arrivingWhileAFetchIsInFlight_isDropped_andNothingIsQueued() async throws {
        let f = Fixture()
        let fetchGate = SleepGate()
        f.recorder.gate = fetchGate
        let appearing = Task { await f.driver.appeared(phase: .active) }
        try await waitUntil { f.recorder.triggers == [.firstAppearance] }
        try await waitUntil { f.sleeper.parkedCount == 1 }

        // Every other trigger while the first fetch is still running.
        f.sleeper.fire()                                  // a timer tick
        await f.driver.scenePhaseChanged(.inactive)       // a foreground return
        await f.driver.scenePhaseChanged(.active)
        await f.driver.refresh()                          // an explicit Refresh
        f.driver.disappeared()                            // a return to the map
        await f.driver.appeared(phase: .active)
        try await settle()
        #expect(f.recorder.triggers == [.firstAppearance])

        await fetchGate.release()
        await appearing.value
        try await settle()
        #expect(f.recorder.triggers == [.firstAppearance], "a dropped trigger is not replayed when the fetch finishes")

        // And once it has finished, the next trigger fetches again.
        await f.driver.refresh()
        #expect(f.recorder.triggers == [.firstAppearance, .explicit])
    }

    // MARK: - explicit Refresh

    @Test func anExplicitRefresh_fetchesAsExplicit_andWaitsForTheResult() async throws {
        let f = Fixture()

        await f.driver.refresh()

        #expect(f.recorder.triggers == [.explicit])
        #expect(f.recorder.adoptedCount == 0, "nothing was running, so there was nothing to adopt")
    }

    // MARK: - §3.6 "An explicit Refresh adopts a fetch already in flight" (I59 review F2)

    @Test func anExplicitRefresh_arrivingWhileAFetchIsInFlight_adoptsIt_startingNoSecondRequest() async throws {
        let f = Fixture()
        let fetchGate = SleepGate()
        f.recorder.gate = fetchGate
        let appearing = Task { await f.driver.appeared(phase: .active) }
        try await waitUntil { f.recorder.triggers == [.firstAppearance] }

        await f.driver.refresh()    // returns at once: it took the running fetch over

        #expect(f.recorder.adoptedCount == 1, "the screen is told to show its refreshing affordance")
        #expect(f.recorder.triggers == [.firstAppearance], "no second request")
        #expect(f.driver.inFlightTrigger == .explicit)

        await fetchGate.release()
        await appearing.value

        #expect(f.recorder.triggers == [.firstAppearance])
        #expect(f.recorder.effectiveTriggerAtCompletion == [.explicit], "the outcome is read as the Refresh's own, after the await")
        #expect(f.driver.inFlightTrigger == nil)
    }

    @Test func aTickFetch_adoptedByAnExplicitRefresh_isReportedAsExplicit() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }
        let tickGate = SleepGate()
        f.recorder.gate = tickGate
        f.sleeper.fire()
        try await waitUntil { f.recorder.triggers == [.firstAppearance, .periodic] }

        await f.driver.refresh()
        await tickGate.release()
        try await waitUntil { f.recorder.effectiveTriggerAtCompletion.count == 2 }

        #expect(f.recorder.adoptedCount == 1)
        #expect(f.recorder.effectiveTriggerAtCompletion == [.firstAppearance, .explicit])
        #expect(f.recorder.triggers == [.firstAppearance, .periodic])
    }

    @Test func anAutomaticTrigger_arrivingWhileAFetchIsInFlight_neitherAdoptsNorUpgradesIt() async throws {
        let f = Fixture()
        let fetchGate = SleepGate()
        f.recorder.gate = fetchGate
        let appearing = Task { await f.driver.appeared(phase: .active) }
        try await waitUntil { f.recorder.triggers == [.firstAppearance] }
        try await waitUntil { f.sleeper.parkedCount == 1 }

        f.sleeper.fire()
        await f.driver.scenePhaseChanged(.inactive)
        await f.driver.scenePhaseChanged(.active)
        try await settle()
        await fetchGate.release()
        await appearing.value

        #expect(f.recorder.adoptedCount == 0)
        #expect(f.recorder.effectiveTriggerAtCompletion == [.firstAppearance])
    }

    @Test func aSecondExplicitRefresh_whileAnExplicitFetchRuns_doesNotAdoptAgain() async throws {
        let f = Fixture()
        let fetchGate = SleepGate()
        f.recorder.gate = fetchGate
        let refreshing = Task { await f.driver.refresh() }
        try await waitUntil { f.recorder.triggers == [.explicit] }

        await f.driver.refresh()

        #expect(f.recorder.adoptedCount == 0, "it is already the user's refresh; nothing to upgrade")
        await fetchGate.release()
        await refreshing.value
        #expect(f.recorder.triggers == [.explicit])
    }

    // MARK: - §3.6: a stopped timer must not cancel a fetch already running (I59 review F5)

    @Test func aTicksFetch_isNotCancelled_whenTheTimerIsStoppedMidFlight() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }
        let tickGate = SleepGate()
        f.recorder.gate = tickGate
        f.sleeper.fire()
        try await waitUntil { f.recorder.triggers == [.firstAppearance, .periodic] }

        // The app is covered while the tick's request is on the wire: the timer stops, the request
        // must be left to finish (Android's behaviour, and what `disappeared()`'s doc promises) — a
        // cancelled one would be reported as a failure if an explicit Refresh had adopted it.
        await f.driver.scenePhaseChanged(.inactive)
        #expect(f.driver.isTimerRunning == false)
        await tickGate.release()
        try await waitUntil { f.recorder.cancelledAtCompletion.count == 2 }

        #expect(f.recorder.cancelledAtCompletion == [false, false])
    }

    // MARK: - terminal states end POLLING (an explicit Retry is not polling)

    @Test func ending_cancelsTheTimer_andNoAutomaticTriggerFetchesAfterwards() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        try await waitUntil { f.sleeper.parkedCount == 1 }

        f.driver.end()

        #expect(f.driver.isTimerRunning == false)
        try await waitUntil { f.sleeper.parkedCount == 0 }
        f.sleeper.fire()
        await f.driver.scenePhaseChanged(.inactive)
        await f.driver.scenePhaseChanged(.active)
        try await settle()
        #expect(f.recorder.triggers == [.firstAppearance])
        #expect(f.driver.isTimerRunning == false)
    }

    @Test func afterPollingEnded_anExplicitRetryStillFetches_withoutRestartingTheTimer() async throws {
        let f = Fixture()
        await f.driver.appeared(phase: .active)
        f.driver.end()

        await f.driver.refresh()

        #expect(f.recorder.triggers == [.firstAppearance, .explicit])
        #expect(f.driver.isTimerRunning == false)
    }

    // MARK: - lifetime

    @Test func theTimerDoesNotKeepADiscardedDriverAlive() async throws {
        let sleeper = ManualSleeper()
        let recorder = RefreshRecorder()
        weak var weakDriver: MapRefreshDriver?
        do {
            let driver = MapRefreshDriver(
                sleep: { await sleeper.sleep($0) },
                perform: { await recorder.perform($0) }
            )
            weakDriver = driver
            await driver.appeared(phase: .active)
            try await waitUntil { sleeper.parkedCount == 1 }
        }

        #expect(weakDriver == nil, "the timer task must hold the driver weakly, or every map screen would leak its view model")
        sleeper.fire()
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(recorder.triggers == [.firstAppearance], "a tick for a driver that no longer exists must not fetch")
    }
}
