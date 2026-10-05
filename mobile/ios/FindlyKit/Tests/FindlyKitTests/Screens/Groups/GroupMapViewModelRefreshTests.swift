import Combine
import Foundation
import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.2/§3.6 (rows A55/I59), §10 "Data freshness" — the group map
/// is covered by §3.6 exactly like the family map: re-fetch on first appearance, foreground return and
/// every 30 s while visible and foregrounded; a failed periodic/foreground refresh keeps the last data
/// silently; a first-load failure and an explicit Refresh still report theirs; no refresh moves the
/// camera; one request in flight. Plus the group-specific terminal state: `410 GROUP_EXPIRED` ends the
/// schedule (there is nothing left to poll).
@MainActor
struct GroupMapViewModelRefreshTests {

    @MainActor
    private final class Harness {
        let api = FakeAPIClient()
        let sleeper = ManualSleeper()
        let viewModel: GroupMapViewModel
        private(set) var emitted: [GroupMapViewModel.State] = []
        private var cancellable: AnyCancellable?

        init() {
            let sleeper = self.sleeper
            viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1", refreshSleep: { await sleeper.sleep($0) })
            cancellable = viewModel.$state.sink { [unowned self] in self.emitted.append($0) }
        }

        func serve(_ members: [GroupMemberLocation]) {
            api.getGroupLatestLocationsHandler = { _ in TestFeatures.envelope(GroupLatestLocationsResponse(members: members)) }
        }

        func fail(_ code: APIErrorCode = .internalError, status: Int = 500) {
            api.getGroupLatestLocationsHandler = { _ in
                throw APIError.server(APIErrorBody(code: code, message: "boom", details: nil, requestId: "r1"), httpStatus: status)
            }
        }

        /// The NEXT fetch parks on `gate` and then fails — a request held "in flight".
        func failAfter(_ gate: SleepGate) {
            api.getGroupLatestLocationsHandler = { _ in
                await gate.wait()
                throw APIError.server(APIErrorBody(code: .internalError, message: "boom", details: nil, requestId: "r1"), httpStatus: 500)
            }
        }

        /// The NEXT fetch parks on `gate` and then succeeds with `members`.
        func serveAfter(_ gate: SleepGate, _ members: [GroupMemberLocation]) {
            api.getGroupLatestLocationsHandler = { _ in
                await gate.wait()
                return TestFeatures.envelope(GroupLatestLocationsResponse(members: members))
            }
        }

        /// A tick's fetch has fully finished once the timer has re-armed (it sleeps only after the
        /// tick returns), so a parked sleep means "that fetch is done".
        func waitForTimerToRearm() async throws {
            try await waitUntil { self.sleeper.parkedCount == 1 }
        }
    }

    private static func member(_ userId: String, _ name: String, lat: Double?, lon: Double?) -> GroupMemberLocation {
        GroupMemberLocation(
            userId: userId, displayName: name, role: "member",
            location: lat.map { GroupPosition(lat: $0, lon: lon!, accuracyM: 10, recordedAt: "2026-10-05T09:00:00Z", receivedAt: "2026-10-05T09:00:02Z", isStale: false) }
        )
    }

    private static let eric = member("u1", "Eric", lat: 51.0, lon: 3.7)
    private static let ericMovedAndNoorJoined = [
        member("u1", "Eric", lat: 51.2, lon: 3.9),
        member("u2", "Noor", lat: 48.0, lon: 2.3),
    ]

    private func isError(_ state: GroupMapViewModel.State) -> Bool {
        if case .error = state { return true }
        return false
    }

    @Test func firstAppearance_loadsTheGroupRoster() async {
        let h = Harness()
        h.serve([Self.eric])

        await h.viewModel.refreshDriver.appeared(phase: .active)

        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.api.getGroupLatestLocationsCalls == ["grp_1"])
    }

    @Test func appearingWhileNotForegrounded_fetchesNothing_untilTheAppComesBack() async {
        let h = Harness()
        h.serve([Self.eric])

        await h.viewModel.refreshDriver.appeared(phase: .background)
        #expect(h.api.getGroupLatestLocationsCalls.isEmpty)
        #expect(h.sleeper.requestedDurations.isEmpty, "no timer in the background")

        await h.viewModel.refreshDriver.scenePhaseChanged(.active)
        #expect(h.viewModel.state == .loaded([Self.eric]))
    }

    @Test func aTimerTick_refetches_withoutEverFlashingTheLoadingState() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        let emittedBefore = h.emitted.count

        h.serve(Self.ericMovedAndNoorJoined)
        h.sleeper.fire()
        try await waitUntil { h.viewModel.state == .loaded(Self.ericMovedAndNoorJoined) }

        #expect(h.api.getGroupLatestLocationsCalls.count == 2)
        #expect(h.emitted.dropFirst(emittedBefore).contains(.loading) == false)
        #expect(h.viewModel.annotations.count == 2)
    }

    @Test func aTimerTick_thatReturnsTheSameRoster_doesNotRepublishTheState() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        let emittedBefore = h.emitted.count

        h.sleeper.fire()
        try await waitUntil { h.api.getGroupLatestLocationsCalls.count == 2 }
        try await h.waitForTimerToRearm()

        #expect(h.emitted.count == emittedBefore)
    }

    @Test func aFailedTimerTick_keepsTheLastData_withNoErrorSurface() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail()
        h.sleeper.fire()
        try await waitUntil { h.api.getGroupLatestLocationsCalls.count == 2 }
        try await h.waitForTimerToRearm()

        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.emitted.contains(where: isError) == false)
    }

    @Test func aFailedForegroundReturn_keepsTheLastData_withNoErrorSurface() async {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        await h.viewModel.refreshDriver.scenePhaseChanged(.background)

        h.fail()
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)

        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.emitted.contains(where: isError) == false)
    }

    @Test func aFirstLoadFailure_showsTheErrorState() async {
        let h = Harness()
        h.fail(.groupNotFound, status: 404)

        await h.viewModel.refreshDriver.appeared(phase: .active)

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

    @Test func aGroupThatExpiresBetweenPolls_endsTheScreen_andStopsPolling() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail(.groupExpired, status: 410)
        h.sleeper.fire()

        try await waitUntil { h.viewModel.state == .expired }
        #expect(h.viewModel.refreshDriver.isTimerRunning == false, "an ended group has nothing left to poll")
    }

    // MARK: - §3.6 "confirmed state change" on the group map (I59 review F1; 001 §12.10, 010 §2.1)
    // A removed member, a deleted/swept group and a deleted profile are each guaranteed to 404/410 on
    // every later poll — they must surface exactly as on a first load and END polling, whatever
    // triggered the fetch, instead of leaving a frozen roster on a 30 s loop.

    @Test func aGroupNotFound_onATimerTick_withDataLoaded_showsTheErrorState_andStopsPolling() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail(.groupNotFound, status: 404)
        h.sleeper.fire()

        try await waitUntil { h.viewModel.state != .loaded([Self.eric]) }
        #expect(isError(h.viewModel.state), "the same outcome as a first load of a vanished group — not a frozen roster")
        #expect(h.viewModel.refreshDriver.isTimerRunning == false)
        #expect(h.viewModel.annotations.isEmpty)
    }

    @Test func aGroupNotFound_onAForegroundReturn_alsoSurfacesAndEndsPolling() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        await h.viewModel.refreshDriver.scenePhaseChanged(.background)

        h.fail(.groupNotFound, status: 404)
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)

        #expect(isError(h.viewModel.state))
        #expect(h.viewModel.refreshDriver.isTimerRunning == false)
    }

    @Test func afterAConfirmedGroupNotFound_noFurtherPollFires_butRetryStillWorks() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        h.fail(.groupNotFound, status: 404)
        h.sleeper.fire()
        try await waitUntil { self.isError(h.viewModel.state) }
        let callsAtEnd = h.api.getGroupLatestLocationsCalls.count

        // Backgrounding and returning no longer fetches…
        await h.viewModel.refreshDriver.scenePhaseChanged(.background)
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)
        h.sleeper.fire()
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(h.api.getGroupLatestLocationsCalls.count == callsAtEnd)

        // …but the error card's Retry is a tap, not polling, and must not be a dead button.
        h.serve([Self.eric])
        await h.viewModel.load()
        #expect(h.api.getGroupLatestLocationsCalls.count == callsAtEnd + 1)
        #expect(h.viewModel.state == .loaded([Self.eric]))
        #expect(h.viewModel.refreshDriver.isTimerRunning == false, "a Retry does not resume polling")
    }

    @Test func aProfileNotFound_onATimerTick_routesToOnboarding_andStopsPolling() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail(.profileNotFound, status: 404)
        h.sleeper.fire()

        try await waitUntil { h.viewModel.state == .routeToOnboarding(.profileLess) }
        #expect(h.viewModel.refreshDriver.isTimerRunning == false)
    }

    @Test func aProfileNotFound_onAForegroundReturn_routesToOnboarding_andStopsPolling() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        await h.viewModel.refreshDriver.scenePhaseChanged(.background)

        h.fail(.profileNotFound, status: 404)
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)

        #expect(h.viewModel.state == .routeToOnboarding(.profileLess))
        #expect(h.viewModel.refreshDriver.isTimerRunning == false)
    }

    @Test func aProfileNotFound_onTheFirstLoad_routesToOnboarding() async {
        let h = Harness()
        h.fail(.profileNotFound, status: 404)

        await h.viewModel.refreshDriver.appeared(phase: .active)

        #expect(h.viewModel.state == .routeToOnboarding(.profileLess))
    }

    @Test func aFamilyNotFound_onTheGroupMap_isAnOrdinaryFailure_keepingTheDataAndPollingOn() async throws {
        // 010 §2.1: group screens need a PROFILE, not a family — a family-less member of a group is
        // legitimate, so `FAMILY_NOT_FOUND` here is not a confirmed state change.
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()

        h.fail(.familyNotFound, status: 404)
        h.sleeper.fire()
        try await waitUntil { h.api.getGroupLatestLocationsCalls.count == 2 }
        try await h.waitForTimerToRearm()

        #expect(h.viewModel.state == .loaded([Self.eric]), "silent, with data on screen")
        #expect(h.emitted.contains(where: isError) == false)
        #expect(h.viewModel.refreshDriver.isTimerRunning, "still polling")
    }

    @Test func aFamilyNotFound_onTheGroupMapsFirstLoad_isAnOrdinaryError_notAnOnboardingRoute() async {
        let h = Harness()
        h.fail(.familyNotFound, status: 404)

        await h.viewModel.refreshDriver.appeared(phase: .active)

        #expect(isError(h.viewModel.state))
    }

    // MARK: - §3.6 "An explicit Refresh adopts a fetch already in flight" (I59 review F2)

    @Test func anExplicitRefresh_arrivingDuringATick_adoptsIt_showsTheRefreshingState_andReportsItsFailure() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        let gate = SleepGate()
        h.failAfter(gate)
        h.sleeper.fire()
        try await waitUntil { h.api.getGroupLatestLocationsCalls.count == 2 }

        await h.viewModel.load()

        #expect(h.api.getGroupLatestLocationsCalls.count == 2, "no second request")
        #expect(h.viewModel.state == .loading)

        await gate.release()
        try await h.waitForTimerToRearm()
        #expect(isError(h.viewModel.state), "reported as the Refresh's own failure, never silent")
    }

    // MARK: - §3.6 / §3.5: a selection made while a fetch is in flight survives it (I59 review F4)

    @Test func aSelectionMadeWhileATickIsInFlight_survivesIt_andMintsNoCameraCommandOfItsOwn() async throws {
        let h = Harness()
        h.serve([Self.eric])
        await h.viewModel.refreshDriver.appeared(phase: .active)
        try await h.waitForTimerToRearm()
        let gate = SleepGate()
        h.serveAfter(gate, Self.ericMovedAndNoorJoined)
        h.sleeper.fire()
        try await waitUntil { h.api.getGroupLatestLocationsCalls.count == 2 }

        h.viewModel.selectMember("u1")
        let sequenceAfterSelection = h.viewModel.cameraCommand?.sequence
        let regionAfterSelection = h.viewModel.region
        #expect(h.viewModel.selectedUserId == "u1")

        await gate.release()
        try await waitUntil { h.viewModel.state == .loaded(Self.ericMovedAndNoorJoined) }

        #expect(h.viewModel.selectedUserId == "u1")
        #expect(h.viewModel.cameraCommand?.sequence == sequenceAfterSelection)
        #expect(h.viewModel.region == regionAfterSelection)
    }

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

    @Test func aTriggerArrivingWhileAFetchIsInFlight_isDropped_notQueued() async throws {
        let h = Harness()
        let gate = SleepGate()
        h.api.getGroupLatestLocationsHandler = { _ in
            await gate.wait()
            return TestFeatures.envelope(GroupLatestLocationsResponse(members: [Self.eric]))
        }
        let appearing = Task { await h.viewModel.refreshDriver.appeared(phase: .active) }
        try await waitUntil { h.api.getGroupLatestLocationsCalls.count == 1 }
        try await waitUntil { h.sleeper.parkedCount == 1 }

        h.sleeper.fire()
        await h.viewModel.refreshDriver.scenePhaseChanged(.inactive)
        await h.viewModel.refreshDriver.scenePhaseChanged(.active)
        await h.viewModel.refreshDriver.refresh()
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(h.api.getGroupLatestLocationsCalls.count == 1)

        await gate.release()
        await appearing.value
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(h.api.getGroupLatestLocationsCalls.count == 1, "dropped, not queued")
        #expect(h.viewModel.state == .loaded([Self.eric]))
    }
}
