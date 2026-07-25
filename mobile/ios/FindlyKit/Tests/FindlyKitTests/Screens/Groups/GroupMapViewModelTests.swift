import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §3.4 (001 §12.10; 005 §3) — the group map: position-only (no
/// `deviceId`/`deviceName`/`batteryPct`/`source`, unlike the family map's `LiveMapViewModel`), and
/// only reachable on `active` groups — `410 GROUP_EXPIRED` bounces the caller back to the groups
/// list (005 §2.3), mirrored here as `.expired` rather than `.error`.
@MainActor
struct GroupMapViewModelTests {

    @Test func initialState_isLoading() {
        let viewModel = GroupMapViewModel(apiClient: FakeAPIClient(), groupId: "grp_1")
        #expect(viewModel.state == .loading)
    }

    @Test func load_success_populatesStateAndAnnotations() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { groupId in
            #expect(groupId == "grp_1")
            return TestFeatures.envelope(GroupLatestLocationsResponse(members: [
                GroupMemberLocation(
                    userId: "u1", displayName: "Eric", role: "owner",
                    location: GroupPosition(lat: 51.0543, lon: 3.7174, accuracyM: 15.0, recordedAt: "2026-07-21T09:58:00Z", receivedAt: "2026-07-21T09:58:02Z", isStale: false)
                ),
                GroupMemberLocation(userId: "u9", displayName: "Noor", role: "member", location: nil),
            ]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")

        await viewModel.load()

        guard case .loaded(let members) = viewModel.state else {
            Issue.record("expected .loaded state, got \(viewModel.state)")
            return
        }
        #expect(members.count == 2)
        #expect(viewModel.annotations.count == 1)
        #expect(viewModel.annotations.first?.id == "u1")
        #expect(viewModel.annotations.first?.initials == "ER")
        #expect(viewModel.annotations.first?.isStale == false)
        #expect(viewModel.region == MapRegion(centerLat: 51.0543, centerLon: 3.7174))
    }

    @Test func annotations_excludeMembersWithNoPositionYet() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [
                GroupMemberLocation(userId: "u9", displayName: "Noor", role: "member", location: nil)
            ]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")

        await viewModel.load()

        #expect(viewModel.annotations.isEmpty)
        #expect(viewModel.region == .findlyDefault)
    }

    @Test func load_groupExpired_setsExpiredState() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            throw APIError.server(APIErrorBody(code: .groupExpired, message: "expired", details: nil, requestId: "r1"), httpStatus: 410)
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")

        await viewModel.load()

        #expect(viewModel.state == .expired)
    }

    @Test func load_otherFailure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            throw APIError.server(APIErrorBody(code: .groupNotFound, message: "not found", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }
}
