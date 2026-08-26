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
        // specs/010-app-shell-and-screen-ux.md §3.2/§3.4 (I35) — one distinct located point on the
        // first load is `MapCameraPolicy`'s `.center` target, not the retired "first annotation,
        // fixed 0.05° span" behavior.
        #expect(viewModel.region == MapRegion(fitting: .center(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.singlePointZoom)))
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
        // specs/010 §3.2/§3.4 (I35) — zero located points is `MapCameraPolicy`'s `.defaultRegion`
        // target, not the retired "stay at `.findlyDefault`'s 0.05° span" behavior.
        #expect(viewModel.region == MapRegion(fitting: .defaultRegion(lat: MapCameraPolicy.defaultLat, lon: MapCameraPolicy.defaultLon, zoom: MapCameraPolicy.defaultZoom)))
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

/// specs/010-app-shell-and-screen-ux.md §3.2/§3.4/§3.5 (I35) — the group map adopts the SAME
/// camera policy and selection behavior as the family map (§3.2: "the same camera policy through
/// the same renderer seam"), position-only: there is exactly one point per member, so selection
/// targets it directly rather than resolving a freshest device.
@MainActor
struct GroupMapViewModelCameraTests {

    private func member(_ userId: String, _ displayName: String, lat: Double?, lon: Double?) -> GroupMemberLocation {
        GroupMemberLocation(
            userId: userId, displayName: displayName, role: "member",
            location: lat.map { GroupPosition(lat: $0, lon: lon!, accuracyM: 10, recordedAt: "2026-08-26T09:00:00Z", receivedAt: "2026-08-26T09:00:02Z", isStale: false) }
        )
    }

    @Test func aRefreshThatChangesThePointSet_mintsNoNewCameraCommand() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [self.member("u1", "Eric", lat: 51.0, lon: 3.7)]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")
        await viewModel.load()
        let firstSequence = viewModel.cameraCommand?.sequence
        let regionAfterFirstLoad = viewModel.region

        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [
                self.member("u1", "Eric", lat: 52.0, lon: 4.7),
                self.member("u2", "Noor", lat: 48.0, lon: 2.3),
            ]))
        }
        await viewModel.load()

        #expect(viewModel.cameraCommand?.sequence == firstSequence)
        #expect(viewModel.region == regionAfterFirstLoad)
    }

    @Test func selectMember_withAPosition_selectsAndZoomsToIt() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [self.member("u1", "Eric", lat: 41.0, lon: 2.0)]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")
        await viewModel.load()
        let sequenceAfterLoad = viewModel.cameraCommand?.sequence

        viewModel.selectMember("u1")

        #expect(viewModel.selectedUserId == "u1")
        #expect(viewModel.cameraCommand?.sequence != sequenceAfterLoad)
        #expect(viewModel.cameraCommand?.target == .center(lat: 41.0, lon: 2.0, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func selectMember_withNoPosition_selectsButDoesNotMoveTheCamera() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [self.member("u1", "Eric", lat: nil, lon: nil)]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")
        await viewModel.load()
        let sequenceAfterLoad = viewModel.cameraCommand?.sequence

        viewModel.selectMember("u1")

        #expect(viewModel.selectedUserId == "u1")
        #expect(viewModel.cameraCommand?.sequence == sequenceAfterLoad)
    }

    @Test func selectingTheAlreadySelectedMember_deselects() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [self.member("u1", "Eric", lat: 41.0, lon: 2.0)]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")
        await viewModel.load()
        viewModel.selectMember("u1")
        #expect(viewModel.selectedUserId == "u1")

        viewModel.selectMember("u1")

        #expect(viewModel.selectedUserId == nil)
    }

    @Test func fitAll_alwaysMintsANewCameraCommand() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [self.member("u1", "Eric", lat: 51.0, lon: 3.7)]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")
        await viewModel.load()
        await viewModel.load()
        let steadySequence = viewModel.cameraCommand?.sequence

        viewModel.fitAll()

        #expect(viewModel.cameraCommand?.sequence != steadySequence)
    }

    @Test func selectingAMember_marksOnlyTheirOwnAnnotationSelected() async {
        let api = FakeAPIClient()
        api.getGroupLatestLocationsHandler = { _ in
            TestFeatures.envelope(GroupLatestLocationsResponse(members: [
                self.member("u1", "Eric", lat: 51.0, lon: 3.7),
                self.member("u2", "Noor", lat: 48.0, lon: 2.3),
            ]))
        }
        let viewModel = GroupMapViewModel(apiClient: api, groupId: "grp_1")
        await viewModel.load()

        viewModel.selectMember("u1")

        #expect(viewModel.annotations.first { $0.id == "u1" }?.isSelected == true)
        #expect(viewModel.annotations.first { $0.id == "u2" }?.isSelected == false)
    }
}
