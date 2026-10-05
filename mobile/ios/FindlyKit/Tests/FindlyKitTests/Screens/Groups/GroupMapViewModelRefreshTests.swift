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
