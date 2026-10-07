import Testing
@testable import FindlyKit

/// specs/011 §2; specs/010 §3.3/§3.4/§3.5 — dormant devices get no marker, no roster chip and take
/// no part in the camera fit or the freshest-device choice; an all-dormant member renders
/// `No recent location`, stays selectable, and every member always appears.
@MainActor
struct DormantPartitioningTests {
    private func device(
        _ id: String, lat: Double? = 51.0, lon: Double? = 3.7, recordedAt: String? = "2026-10-07T09:00:00Z",
        dormant: Bool = false
    ) -> DeviceLocation {
        DeviceLocation(
            deviceId: id, deviceName: "Device \(id)", lat: lat, lon: lon, accuracyM: lat == nil ? nil : 10,
            recordedAt: recordedAt, receivedAt: recordedAt, batteryPct: nil, source: lat == nil ? nil : .periodic,
            trackingEnabled: true, syncIntervalMinutes: 15, isStale: false, isDormant: dormant
        )
    }

    private func loaded(_ members: [MemberLocations]) async -> LiveMapViewModel {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = { TestFeatures.envelope(LatestLocationsResponse(members: members)) }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        return viewModel
    }

    // MARK: markers

    @Test func dormantDevices_getNoMarker() async {
        let viewModel = await loaded([
            MemberLocations(userId: "u1", displayName: "Eric", devices: [device("live"), device("ghost", dormant: true)])
        ])
        #expect(viewModel.annotations.map(\.id) == ["live"])
    }

    // MARK: camera fit

    @Test func initialFit_ignoresDormantDevices() async {
        let viewModel = await loaded([
            MemberLocations(userId: "u1", displayName: "Eric", devices: [
                device("live", lat: 51.0, lon: 3.7), device("ghost", lat: 10.0, lon: 10.0, dormant: true)
            ])
        ])
        // One live point -> single-point centering, not a bounds fit that drags in the ghost.
        #expect(viewModel.cameraCommand?.target == .center(lat: 51.0, lon: 3.7, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func fitAll_ignoresDormantDevices() async {
        let viewModel = await loaded([
            MemberLocations(userId: "u1", displayName: "Eric", devices: [
                device("live", lat: 51.0, lon: 3.7), device("ghost", lat: 10.0, lon: 10.0, dormant: true)
            ])
        ])
        viewModel.fitAll()
        #expect(viewModel.cameraCommand?.target == .center(lat: 51.0, lon: 3.7, zoom: MapCameraPolicy.singlePointZoom))
    }

    // MARK: freshest device

    @Test func freshestLocatedDevice_skipsANewerDormantDevice() {
        let devices = [
            device("live", lat: 51.0, lon: 3.7, recordedAt: "2026-10-07T08:00:00Z"),
            device("ghost", lat: 10.0, lon: 10.0, recordedAt: "2026-10-07T09:00:00Z", dormant: true)
        ]
        #expect(MapCameraPolicy.freshestLocatedDevice(devices: devices)?.deviceId == "live")
    }

    @Test func freshestLocatedDevice_isNilWhenEveryDeviceIsDormant() {
        #expect(MapCameraPolicy.freshestLocatedDevice(devices: [device("ghost", dormant: true)]) == nil)
    }

    @Test func selectingAnAllDormantMember_selectsIt_withoutMovingTheCamera() async {
        let viewModel = await loaded([
            MemberLocations(userId: "u1", displayName: "Eric", devices: [device("live")]),
            MemberLocations(userId: "u2", displayName: "Noor", devices: [device("ghost", dormant: true)])
        ])
        let sequenceBefore = viewModel.cameraCommand?.sequence

        viewModel.selectMember("u2")

        #expect(viewModel.selectedUserId == "u2")
        #expect(viewModel.cameraCommand?.sequence == sequenceBefore)
    }

    @Test func everyMemberStillAppearsInTheLoadedRoster() async {
        let members = [
            MemberLocations(userId: "u1", displayName: "Eric", devices: [device("ghost", dormant: true)]),
            MemberLocations(userId: "u2", displayName: "Noor", devices: [])
        ]
        let viewModel = await loaded(members)
        #expect(viewModel.state == .loaded(members))
    }

    // MARK: roster rows

    @Test func rosterPlan_dropsDormantChips_keepingLiveOnes_firstMarkedFirst() {
        let plan = RosterRowPlan.compute(devices: [device("ghost", dormant: true), device("a"), device("b")])
        #expect(plan.rows.compactMap { $0.device?.deviceId } == ["a", "b"])
        #expect(plan.rows.map(\.isFirst) == [true, false])
        #expect(plan.interRowDividerCount == 1)
    }

    @Test func rosterPlan_allDormant_yieldsOneNoRecentLocationRow() {
        let plan = RosterRowPlan.compute(devices: [device("g1", dormant: true), device("g2", dormant: true)])
        #expect(plan.rows.count == 1)
        #expect(plan.rows[0].device == nil)
        #expect(plan.rows[0].emptyState == .noRecentLocation)
        #expect(plan.rows[0].emptyState?.text == "No recent location")
        #expect(plan.interRowDividerCount == 0)
    }

    @Test func rosterPlan_noDevicesAtAll_keepsTheNoDevicesRow() {
        let plan = RosterRowPlan.compute(devices: [])
        #expect(plan.rows.count == 1)
        #expect(plan.rows[0].emptyState == .noDevices)
        #expect(plan.rows[0].emptyState?.text == "No devices registered")
    }
}
