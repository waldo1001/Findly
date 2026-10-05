import Combine
import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.6 (rows A55/I59), §10 "Data freshness" — the family map's
/// view model on the refresh driver: first appearance, foreground return and the 30 s timer all
/// re-fetch the roster; a failed periodic/foreground refresh keeps the last data with no error
/// surface while a first-load failure and an explicit Refresh still report theirs; no refresh moves
/// the camera or changes the selection; at most one request is in flight.
@MainActor
struct LiveMapViewModelRefreshTests {

    @MainActor
    private final class Harness {
        let api = FakeAPIClient()
        let sleeper = ManualSleeper()
        let viewModel: LiveMapViewModel
        /// Every value `state` took, in order (the initial `.loading` included).
        private(set) var emitted: [LiveMapViewModel.State] = []
        private var cancellable: AnyCancellable?

        init() {
            let sleeper = self.sleeper
            viewModel = LiveMapViewModel(apiClient: api, refreshSleep: { await sleeper.sleep($0) })
            cancellable = viewModel.$state.sink { [unowned self] in self.emitted.append($0) }
        }

        func serve(_ members: [MemberLocations]) {
            api.getLatestLocationsHandler = { TestFeatures.envelope(LatestLocationsResponse(members: members)) }
        }

        func fail(_ code: APIErrorCode = .internalError, status: Int = 500) {
            api.getLatestLocationsHandler = {
                throw APIError.server(APIErrorBody(code: code, message: "boom", details: nil, requestId: "r1"), httpStatus: status)
            }
        }

        /// The point at which a timer tick's fetch has fully finished: the timer re-arms only after
        /// the tick returns, so a parked sleep means "that fetch is done".
        func waitForTimerToRearm() async throws {
            try await waitUntil { self.sleeper.parkedCount == 1 }
        }
    }

    private static let eric = MemberLocations(userId: "u1", displayName: "Eric", devices: [device("d1", lat: 51.0, lon: 3.7)])
    private static let ericMovedAndNoorJoined = [
        MemberLocations(userId: "u1", displayName: "Eric", devices: [device("d1", lat: 51.2, lon: 3.9, recordedAt: "2026-10-05T09:30:00Z")]),
        MemberLocations(userId: "u2", displayName: "Noor", devices: [device("d2", lat: 48.0, lon: 2.3)]),
    ]

    private static func device(_ id: String, lat: Double, lon: Double, recordedAt: String = "2026-10-05T09:00:00Z") -> DeviceLocation {
        DeviceLocation(
            deviceId: id, deviceName: "Device \(id)", lat: lat, lon: lon, accuracyM: 10,
            recordedAt: recordedAt, receivedAt: recordedAt, batteryPct: 80, source: .periodic,
            trackingEnabled: true, syncIntervalMinutes: 15, isStale: false
        )
    }

    private func isError(_ state: LiveMapViewModel.State) -> Bool {
        if case .error = state { return true }
        return false
    }

    // MARK: - §3.6 #1 first appearance

    @Test func firstAppearance_loadsTheRoster() async {
        let h = Harness()
        h.serve([Self.eric])

        await h.viewModel.refreshDriver.appeared(phase: .active)

        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.api.getLatestLocationsCallCount == 1)
    }

    @Test func appearingWhileNotForegrounded_fetchesNothing_untilTheAppComesBack() async throws {
        let h = Harness()
        h.serve([Self.eric])

        await h.viewModel.refreshDriver.appeared(phase: .background)
        #expect(h.api.getLatestLocationsCallCount == 0)
        #expect(h.sleeper.requestedDurations.isEmpty, "no timer in the background")
        #expect(h.viewModel.state == .loading)

        await h.viewModel.refreshDriver.scenePhaseChanged(.active)
        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.api.getLatestLocationsCallCount == 1)
    }

    // MARK: - §3.6 #3 every 30 s while visible + foregrounded

    @Test func aTimerTick_refetches_showingFresherPositions_withoutEverFlashingTheLoadingState() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        let emittedBefore = h.emitted.count

        h.serve(Self.ericMovedAndNoorJoined)
        h.sleeper.fire()
        try await waitUntil { h.viewModel.state == .loaded(Self.ericMovedAndNoorJoined) }

        #expect(h.api.getLatestLocationsCallCount == 2)
        #expect(h.emitted.dropFirst(emittedBefore).contains(.loading) == false, "a periodic refresh must never blank the map and roster behind a spinner")
        #expect(h.viewModel.annotations.count == 2)
    }

    @Test func aTimerTick_thatReturnsTheSameRoster_doesNotRepublishTheState() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        let emittedBefore = h.emitted.count

        h.sleeper.fire()
        try await waitUntil { h.api.getLatestLocationsCallCount == 2 }
        try await h.waitForTimerToRearm()

        #expect(h.emitted.count == emittedBefore, "an unchanged poll must not re-render the sheet every 30 s")
    }

    // MARK: - §3.6: failures

    @Test func aFailedTimerTick_keepsTheLastData_withNoErrorSurface() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail()
        h.sleeper.fire()
        try await waitUntil { h.api.getLatestLocationsCallCount == 2 }
        try await h.waitForTimerToRearm()

        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.emitted.contains(where: isError) == false)
        #expect(h.viewModel.annotations.count == 1, "the markers stay on the map")
    }

    @Test func aFailedForegroundReturn_keepsTheLastData_withNoErrorSurface() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        await h.viewModel.refreshDriver.scenePhaseChanged(.background)

        h.fail()
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)

        #expect(h.api.getLatestLocationsCallCount == 2)
        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.emitted.contains(where: isError) == false)
    }

    @Test func aFirstLoadFailure_showsTheErrorState() async {
        let h = Harness()
        h.fail()

        await h.viewModel.refreshDriver.appeared(phase: .active)

        #expect(isError(h.viewModel.state))
    }

    @Test func aFirstLoadThatHadToWaitForTheForeground_stillReportsItsFailure() async {
        let h = Harness()
        h.fail()
        await h.viewModel.refreshDriver.appeared(phase: .background)

        await h.viewModel.refreshDriver.scenePhaseChanged(.active)

        #expect(isError(h.viewModel.state), "still a first load — there is no data to keep")
    }

    @Test func aTimerTick_afterAFailedFirstLoad_recoversTheMapWhenTheServerIsBack() async throws {
        let h = Harness()
        h.fail()
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        #expect(isError(h.viewModel.state))

        h.serve([Self.eric])
        h.sleeper.fire()

        try await waitUntil { h.viewModel.state == .loaded([Self.eric]) }
    }

    @Test func aFailedTimerTick_whileShowingTheFirstLoadError_staysOnTheErrorState() async throws {
        let h = Harness()
        h.fail()
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.sleeper.fire()
        try await waitUntil { h.api.getLatestLocationsCallCount == 2 }
        try await h.waitForTimerToRearm()

        #expect(isError(h.viewModel.state))
    }

    @Test func anExplicitRefresh_thatFails_reportsItsOwnFailure_evenWithDataOnScreen() async {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        h.fail()

        await h.viewModel.load()

        #expect(isError(h.viewModel.state))
    }

    @Test func anExplicitRefresh_stillShowsTheLoadingStateWhileItRuns() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        let gate = SleepGate()
        h.api.getLatestLocationsHandler = {
            await gate.wait()
            return TestFeatures.envelope(LatestLocationsResponse(members: [Self.eric]))
        }

        let refreshing = Task { await h.viewModel.load() }
        try await waitUntil { h.viewModel.state == .loading }
        await gate.release()
        await refreshing.value

        #expect(h.viewModel.state == .loaded([Self.eric]))
    }

    @Test func aRoutedProfileDeadEnd_onATimerTick_routesToOnboarding_andStopsPolling() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail(.familyNotFound, status: 404)
        h.sleeper.fire()

        try await waitUntil { h.viewModel.state == .routeToOnboarding(.familyLess) }
        #expect(h.viewModel.refreshDriver.isTimerRunning == false, "a confirmed dead end has nothing left to poll")
    }

    // MARK: - §3.6 / §3.4: a refresh never moves the camera or the selection

    @Test func aTimerTick_withChangedPoints_neverMovesTheCamera_orChangesTheSelection() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        h.viewModel.selectMember("u1")
        let sequence = h.viewModel.cameraCommand?.sequence
        let region = h.viewModel.region
        try await h.waitForTimerToRearm()

        h.serve(Self.ericMovedAndNoorJoined)
        h.sleeper.fire()
        try await waitUntil { h.viewModel.state == .loaded(Self.ericMovedAndNoorJoined) }

        #expect(h.viewModel.cameraCommand?.sequence == sequence)
        #expect(h.viewModel.region == region)
        #expect(h.viewModel.selectedUserId == "u1")
    }

    @Test func aForegroundReturn_withChangedPoints_neverMovesTheCamera() async {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        let sequence = h.viewModel.cameraCommand?.sequence
        let region = h.viewModel.region
        await h.viewModel.refreshDriver.scenePhaseChanged(.background)

        h.serve(Self.ericMovedAndNoorJoined)
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)

        #expect(h.viewModel.state == .loaded(Self.ericMovedAndNoorJoined))
        #expect(h.viewModel.cameraCommand?.sequence == sequence)
        #expect(h.viewModel.region == region)
    }

    // MARK: - §3.6: at most one request in flight

    @Test func aTriggerArrivingWhileAFetchIsInFlight_isDropped_notQueued() async throws {
        let h = Harness()
        let gate = SleepGate()
        h.api.getLatestLocationsHandler = {
            await gate.wait()
            return TestFeatures.envelope(LatestLocationsResponse(members: [Self.eric]))
        }
        let appearing = Task { await h.viewModel.refreshDriver.appeared(phase: .active) }
        try await waitUntil { h.api.getLatestLocationsCallCount == 1 }
        try await waitUntil { h.sleeper.parkedCount == 1 }

        h.sleeper.fire()                                                 // a tick
        await h.viewModel.refreshDriver.scenePhaseChanged(.inactive)     // a foreground return
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)
        await h.viewModel.refreshDriver.refresh()                        // an explicit Refresh
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(h.api.getLatestLocationsCallCount == 1)

        await gate.release()
        await appearing.value
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(h.api.getLatestLocationsCallCount == 1, "dropped, not queued")
        #expect(h.viewModel.state == .loaded([Self.eric]))
    }
}
