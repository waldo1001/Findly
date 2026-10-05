import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59), §10 "Data freshness" — the pure
/// refresh-trigger policy. Every rule of §3.6 is pinned here as a decision over events, with no
/// SwiftUI, no timers and no network: which events cause a fetch, when the 30 s timer may run, that a
/// trigger during an in-flight fetch is dropped (not queued), and whether a failed fetch may surface
/// an error.
struct MapRefreshPolicyTests {

    typealias Phase = MapRefreshPolicy.ScenePhase

    /// A map that is on screen, in the foreground, and idle — the steady state every §3.6 rule
    /// except "first appearance" starts from.
    private func steadyState() -> MapRefreshPolicy {
        var policy = MapRefreshPolicy()
        policy.handle(.scenePhaseChanged(.active))
        policy.handle(.appeared)
        policy.handle(.fetchFinished)
        return policy
    }

    // MARK: - §3.6 trigger 1: first appearance

    @Test func appearing_whileForegrounded_fetchesAsFirstAppearance() {
        var policy = MapRefreshPolicy()
        policy.handle(.scenePhaseChanged(.active))

        #expect(policy.handle(.appeared) == .fetch(.firstAppearance))
    }

    @Test func appearing_withNoPhaseEverReported_assumesForegroundedAndFetches() {
        var policy = MapRefreshPolicy()

        #expect(policy.handle(.appeared) == .fetch(.firstAppearance))
    }

    @Test func appearing_whileBackgrounded_fetchesNothing_untilTheAppReturnsToTheForeground() {
        var policy = MapRefreshPolicy()
        policy.handle(.scenePhaseChanged(.background))

        #expect(policy.handle(.appeared) == .none)
        #expect(policy.handle(.scenePhaseChanged(.active)) == .fetch(.foregroundReturn))
    }

    @Test func appearing_whileInactive_fetchesNothing() {
        var policy = MapRefreshPolicy()
        policy.handle(.scenePhaseChanged(.inactive))

        #expect(policy.handle(.appeared) == .none)
    }

    @Test func appearingTwiceWithoutDisappearing_fetchesOnlyOnce() {
        var policy = MapRefreshPolicy()
        #expect(policy.handle(.appeared) == .fetch(.firstAppearance))
        policy.handle(.fetchFinished)

        #expect(policy.handle(.appeared) == .none)
    }

    // MARK: - §3.6 trigger 2: every return to the foreground / navigation back to the map

    @Test func returningToTheForegroundFromBackground_whileTheMapIsVisible_fetches() {
        var policy = steadyState()
        policy.handle(.scenePhaseChanged(.inactive))
        policy.handle(.scenePhaseChanged(.background))

        #expect(policy.handle(.scenePhaseChanged(.inactive)) == .none)
        #expect(policy.handle(.scenePhaseChanged(.active)) == .fetch(.foregroundReturn))
    }

    @Test func returningToTheForegroundFromInactive_whileTheMapIsVisible_fetches() {
        var policy = steadyState()
        policy.handle(.scenePhaseChanged(.inactive))

        #expect(policy.handle(.scenePhaseChanged(.active)) == .fetch(.foregroundReturn))
    }

    @Test func leavingTheForeground_neverFetches() {
        var policy = steadyState()

        #expect(policy.handle(.scenePhaseChanged(.inactive)) == .none)
        #expect(policy.handle(.scenePhaseChanged(.background)) == .none)
    }

    @Test func reportingActiveWhileAlreadyActive_isNotAReturnToTheForeground() {
        var policy = steadyState()

        #expect(policy.handle(.scenePhaseChanged(.active)) == .none)
    }

    @Test func returningToTheForeground_afterTheMapLeftTheScreen_doesNotFetch() {
        var policy = steadyState()
        policy.handle(.disappeared)
        policy.handle(.scenePhaseChanged(.background))

        #expect(policy.handle(.scenePhaseChanged(.active)) == .none)
    }

    @Test func navigatingBackToTheMap_fetchesAsReturnToMap_notAsFirstAppearance() {
        var policy = steadyState()
        policy.handle(.disappeared)

        #expect(policy.handle(.appeared) == .fetch(.returnToMap))
    }

    // MARK: - §3.6 trigger 3: every 30 s while visible AND foregrounded — never in the background

    @Test func timerShouldRun_onlyWhileVisibleAndForegrounded() {
        var policy = MapRefreshPolicy()
        #expect(policy.timerShouldRun == false, "not visible yet")

        policy.handle(.appeared)
        #expect(policy.timerShouldRun == true, "visible + foregrounded")

        policy.handle(.scenePhaseChanged(.inactive))
        #expect(policy.timerShouldRun == false, "inactive is not foregrounded")

        policy.handle(.scenePhaseChanged(.background))
        #expect(policy.timerShouldRun == false, "never in the background")

        policy.handle(.scenePhaseChanged(.active))
        #expect(policy.timerShouldRun == true, "foregrounded again")

        policy.handle(.disappeared)
        #expect(policy.timerShouldRun == false, "the map left the screen")
    }

    @Test func timerShouldRun_isFalseWhenTheMapAppearsWhileBackgrounded() {
        var policy = MapRefreshPolicy()
        policy.handle(.scenePhaseChanged(.background))
        policy.handle(.appeared)

        #expect(policy.timerShouldRun == false)
    }

    @Test func timerTick_whileVisibleAndForegrounded_fetchesPeriodically() {
        var policy = steadyState()

        #expect(policy.handle(.timerTick) == .fetch(.periodic))
    }

    @Test(arguments: [Phase.inactive, Phase.background])
    func timerTick_whenNotForegrounded_isIgnored(_ phase: Phase) {
        // The timer task is cancelled on a phase change, but a tick that was already delivered when
        // the phase flipped must still not become a request — "no polling in the background, ever".
        var policy = steadyState()
        policy.handle(.scenePhaseChanged(phase))

        #expect(policy.handle(.timerTick) == .none)
        #expect(policy.isFetching == false)
    }

    @Test func timerTick_whenTheMapIsNotVisible_isIgnored() {
        var policy = steadyState()
        policy.handle(.disappeared)

        #expect(policy.handle(.timerTick) == .none)
    }

    // MARK: - §3.6: at most one request in flight — dropped, never queued

    @Test func firstAppearance_marksAFetchInFlight() {
        var policy = MapRefreshPolicy()
        policy.handle(.appeared)

        #expect(policy.isFetching == true)
    }

    @Test func aTimerTick_arrivingWhileAFetchIsRunning_isDropped() {
        var policy = MapRefreshPolicy()
        policy.handle(.appeared)

        #expect(policy.handle(.timerTick) == .none)
    }

    @Test func aForegroundReturn_arrivingWhileAFetchIsRunning_isDropped() {
        var policy = steadyState()
        policy.handle(.scenePhaseChanged(.inactive))
        #expect(policy.handle(.scenePhaseChanged(.active)) == .fetch(.foregroundReturn))

        policy.handle(.scenePhaseChanged(.inactive))
        #expect(policy.handle(.scenePhaseChanged(.active)) == .none)
    }

    @Test func aReturnToMap_arrivingWhileAFetchIsRunning_isDropped() {
        var policy = MapRefreshPolicy()
        policy.handle(.appeared)
        policy.handle(.disappeared)

        #expect(policy.handle(.appeared) == .none)
    }

    @Test func anExplicitRefresh_arrivingWhileAFetchIsRunning_isDropped() {
        var policy = MapRefreshPolicy()
        policy.handle(.appeared)

        #expect(policy.handle(.explicitRefresh) == .none)
    }

    @Test func aDroppedTrigger_isNotQueued_finishingTheFetchStartsNothing() {
        var policy = MapRefreshPolicy()
        policy.handle(.appeared)
        #expect(policy.handle(.timerTick) == .none)

        #expect(policy.handle(.fetchFinished) == .none)
        #expect(policy.isFetching == false)
    }

    @Test func onceTheFetchFinishes_theNextTriggerFetchesAgain() {
        var policy = MapRefreshPolicy()
        policy.handle(.appeared)
        policy.handle(.fetchFinished)

        #expect(policy.handle(.timerTick) == .fetch(.periodic))
        policy.handle(.fetchFinished)
        #expect(policy.handle(.timerTick) == .fetch(.periodic))
    }

    // MARK: - §3.1 explicit Refresh

    @Test func anExplicitRefresh_fetchesAsExplicit() {
        var policy = steadyState()

        #expect(policy.handle(.explicitRefresh) == .fetch(.explicit))
    }

    // MARK: - terminal states (routed 404, expired group): the schedule stops

    @Test func afterTheScreenEnds_nothingFetchesAndTheTimerStops() {
        var policy = steadyState()
        policy.handle(.ended)

        #expect(policy.isEnded == true)
        #expect(policy.timerShouldRun == false)
        #expect(policy.handle(.timerTick) == .none)
        #expect(policy.handle(.explicitRefresh) == .none)
        policy.handle(.scenePhaseChanged(.background))
        #expect(policy.handle(.scenePhaseChanged(.active)) == .none)
        policy.handle(.disappeared)
        #expect(policy.handle(.appeared) == .none)
    }

    // MARK: - §3.6: which failures may surface an error

    @Test func aFailedExplicitRefresh_alwaysReportsItsOwnFailure_evenWithDataOnScreen() {
        #expect(MapRefreshPolicy.failureOutcome(for: .explicit, hasDataOnScreen: true) == .showError)
        #expect(MapRefreshPolicy.failureOutcome(for: .explicit, hasDataOnScreen: false) == .showError)
    }

    @Test(arguments: [MapRefreshPolicy.Trigger.periodic, .foregroundReturn, .returnToMap, .firstAppearance])
    func aFailedBackgroundRefresh_withDataOnScreen_keepsTheLastDataSilently(_ trigger: MapRefreshPolicy.Trigger) {
        #expect(MapRefreshPolicy.failureOutcome(for: trigger, hasDataOnScreen: true) == .keepLastData)
    }

    @Test(arguments: [MapRefreshPolicy.Trigger.periodic, .foregroundReturn, .returnToMap, .firstAppearance])
    func aFailedLoad_withNoDataOnScreenYet_showsTheErrorState(_ trigger: MapRefreshPolicy.Trigger) {
        // Only a FIRST load failure may show the error state — keyed on "nothing to show yet", not on
        // the trigger's name, so a first load that had to wait for the foreground still reports it.
        #expect(MapRefreshPolicy.failureOutcome(for: trigger, hasDataOnScreen: false) == .showError)
    }
}
