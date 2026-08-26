import Testing
@testable import FindlyKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// specs/004-ios-client.md I2 (001 §5.2) — the family map/roster view model: state transitions,
/// annotation derivation (excluding never-reported devices), and `isStale` passthrough.
@MainActor
struct LiveMapViewModelTests {

    @Test func initialState_isLoading() {
        let viewModel = LiveMapViewModel(apiClient: FakeAPIClient())
        #expect(viewModel.state == .loading)
    }

    @Test func load_success_populatesStateAndAnnotations() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u1", displayName: "Eric", devices: [
                    DeviceLocation(
                        deviceId: "d1", deviceName: "Eric's phone", lat: 51.0, lon: 3.7, accuracyM: 10,
                        recordedAt: "2026-07-19T09:00:00Z", receivedAt: "2026-07-19T09:00:02Z",
                        batteryPct: 80, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false
                    )
                ]),
                MemberLocations(userId: "u2", displayName: "Noor", devices: [])
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded([
            MemberLocations(userId: "u1", displayName: "Eric", devices: [
                DeviceLocation(
                    deviceId: "d1", deviceName: "Eric's phone", lat: 51.0, lon: 3.7, accuracyM: 10,
                    recordedAt: "2026-07-19T09:00:00Z", receivedAt: "2026-07-19T09:00:02Z",
                    batteryPct: 80, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false
                )
            ]),
            MemberLocations(userId: "u2", displayName: "Noor", devices: [])
        ]))
        #expect(viewModel.annotations.count == 1)
        #expect(viewModel.annotations.first?.id == "d1")
        #expect(viewModel.annotations.first?.initials == "ER")
        #expect(viewModel.annotations.first?.isStale == false)
        // specs/010-app-shell-and-screen-ux.md §3.4 (I35) — one distinct located point on the very
        // first load is `MapCameraPolicy`'s `.center` target at `singlePointZoom`, not the retired
        // "first annotation, fixed 0.05° span" behavior.
        #expect(viewModel.region == MapRegion(fitting: .center(lat: 51.0, lon: 3.7, zoom: MapCameraPolicy.singlePointZoom), viewSizePt: viewModel.mapViewportSizePt))
        #expect(viewModel.cameraCommand?.target == .center(lat: 51.0, lon: 3.7, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func annotations_excludeDevicesWithNoFixYet() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u1", displayName: "Eric", devices: [
                    DeviceLocation(
                        deviceId: "d1", deviceName: "New phone", lat: nil, lon: nil, accuracyM: nil,
                        recordedAt: nil, receivedAt: nil, batteryPct: nil, source: nil,
                        trackingEnabled: true, syncIntervalMinutes: 15, isStale: nil
                    )
                ])
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.annotations.isEmpty)
        // specs/010 §3.4 (I35) — zero located points on the very first load is `MapCameraPolicy`'s
        // `.defaultRegion` target (the calm, zoomed-out default), not the retired "stay at
        // `.findlyDefault`'s 0.05° span" behavior.
        #expect(viewModel.region == MapRegion(fitting: .defaultRegion(lat: MapCameraPolicy.defaultLat, lon: MapCameraPolicy.defaultLon, zoom: MapCameraPolicy.defaultZoom), viewSizePt: viewModel.mapViewportSizePt))
    }

    @Test func annotations_missingIsStale_defaultsToStale() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u1", displayName: "Eric", devices: [
                    DeviceLocation(
                        deviceId: "d1", deviceName: "Phone", lat: 51.0, lon: 3.7, accuracyM: 10,
                        recordedAt: "2026-07-19T09:00:00Z", receivedAt: "2026-07-19T09:00:02Z",
                        batteryPct: 80, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: nil
                    )
                ])
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.annotations.first?.isStale == true)
    }

    @Test func load_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            throw APIError.server(APIErrorBody(code: .internalError, message: "boom", details: nil, requestId: "r1"), httpStatus: 500)
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §2.1 (I34) — the profile-dead-end routing rule.
    // `GET /locations/latest` is family-scoped (001 §5.2/§1.5.4), so BOTH 404s are reachable here;
    // neither may render the old retryable error card (a Retry on this load can never succeed).

    @Test func load_profileNotFound_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "no profile", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.profileLess))
    }

    @Test func load_familyNotFound_routesToOnboardingFamilyLess() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "no family", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.familyLess))
    }
}

/// specs/010-app-shell-and-screen-ux.md §3.4/§3.5 (I35) — the mandatory regression this task
/// exists to fix: a refresh (any subsequent call to `load()`) MUST NOT move the camera, even when
/// the point set changed. Also covers §3.5's member-selection → freshest-device zoom, and §3.4's
/// explicit fit-all action. Mirrors Android's `MapStateHolderTest` camera-wiring section.
@MainActor
struct LiveMapViewModelCameraTests {

    private func member(_ userId: String, _ displayName: String, devices: [DeviceLocation]) -> MemberLocations {
        MemberLocations(userId: userId, displayName: displayName, devices: devices)
    }

    private func device(_ id: String, lat: Double?, lon: Double?, recordedAt: String? = "2026-08-26T09:00:00Z") -> DeviceLocation {
        DeviceLocation(
            deviceId: id, deviceName: "Device \(id)", lat: lat, lon: lon, accuracyM: lat == nil ? nil : 10,
            recordedAt: recordedAt, receivedAt: recordedAt, batteryPct: nil, source: lat == nil ? nil : .periodic,
            trackingEnabled: true, syncIntervalMinutes: 15, isStale: false
        )
    }

    @Test func aRefreshThatChangesThePointSet_mintsNoNewCameraCommand() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [self.member("u1", "Eric", devices: [self.device("d1", lat: 51.0, lon: 3.7)])]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()
        let firstCommandSequence = viewModel.cameraCommand?.sequence
        let regionAfterFirstLoad = viewModel.region
        #expect(firstCommandSequence != nil)

        // The refresh returns a DIFFERENT, non-empty point set — the exact "marker set changed"
        // scenario 010 §3.4 says MUST NOT move the camera.
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                self.member("u1", "Eric", devices: [self.device("d1", lat: 52.0, lon: 4.7)]),
                self.member("u2", "Noor", devices: [self.device("d2", lat: 48.0, lon: 2.3)]),
            ]))
        }
        await viewModel.load()

        #expect(viewModel.cameraCommand?.sequence == firstCommandSequence)
        #expect(viewModel.region == regionAfterFirstLoad)
    }

    /// specs/010 §3.4 (amended 2026-08-26, row I39) — proves the view model actually FORWARDS
    /// `mapViewportSizePt` into `MapRegion(fitting:viewSizePt:)` for the `.bounds` (2+ distinct
    /// points) case, and that the resulting span is the fixed-screen-space-margin value, not a
    /// proportional one — asserts the exact resulting region, not merely that a camera command was
    /// minted (a call-count check can't distinguish a correct fit from a wrong one).
    @Test func load_withTwoOrMoreDistinctPoints_fitsBoundsUsingTheLiveViewportSize() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                self.member("u1", "Eric", devices: [self.device("d1", lat: 50.0, lon: 3.0)]),
                self.member("u2", "Noor", devices: [self.device("d2", lat: 51.0, lon: 4.0)]),
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        let viewportSizePt = CGSize(width: 400, height: 800)
        viewModel.mapViewportSizePt = viewportSizePt

        await viewModel.load()

        let expectedTarget = MapCameraTarget.bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: MapCameraPolicy.boundsPaddingPt)
        #expect(viewModel.cameraCommand?.target == expectedTarget)
        #expect(viewModel.region == MapRegion(fitting: expectedTarget, viewSizePt: viewportSizePt))
        // Pin the actual number so a wiring bug (e.g. always using `.unmeasuredViewportSizePt`
        // instead of the property this test set) is caught even if the equality check above were
        // wrong for some unrelated reason.
        #expect(abs(viewModel.region.spanLatDelta - 800.0 / 672.0) < 1e-9)
    }

    @Test func theFirstLoad_evenWithZeroPoints_mintsACameraCommand() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: []))
        }
        let viewModel = LiveMapViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.cameraCommand?.target == .defaultRegion(lat: MapCameraPolicy.defaultLat, lon: MapCameraPolicy.defaultLon, zoom: MapCameraPolicy.defaultZoom))
    }

    @Test func theFirstRefreshThatBringsInTheFirstEverPoint_fromAZeroPointOpen_mintsANewCommand() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: []))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        let firstSequence = viewModel.cameraCommand?.sequence

        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [self.member("u1", "Eric", devices: [self.device("d1", lat: 51.0, lon: 3.7)])]))
        }
        await viewModel.load()

        #expect(viewModel.cameraCommand?.sequence != firstSequence)
        #expect(viewModel.cameraCommand?.target == .center(lat: 51.0, lon: 3.7, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func selectMember_withALocatedDevice_selectsAndZoomsToTheFreshestOne() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                self.member("u1", "Eric", devices: [
                    self.device("older", lat: 40.0, lon: 1.0, recordedAt: "2026-08-26T08:00:00Z"),
                    self.device("newer", lat: 41.0, lon: 2.0, recordedAt: "2026-08-26T09:30:00Z"),
                ])
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        let sequenceAfterLoad = viewModel.cameraCommand?.sequence

        viewModel.selectMember("u1")

        #expect(viewModel.selectedUserId == "u1")
        #expect(viewModel.cameraCommand?.sequence != sequenceAfterLoad)
        #expect(viewModel.cameraCommand?.target == .center(lat: 41.0, lon: 2.0, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func selectMember_withNoLocatedDevice_selectsButDoesNotMoveTheCamera() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                self.member("u1", "Eric", devices: [self.device("d1", lat: nil, lon: nil, recordedAt: nil)])
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        let sequenceAfterLoad = viewModel.cameraCommand?.sequence
        let regionAfterLoad = viewModel.region

        viewModel.selectMember("u1")

        #expect(viewModel.selectedUserId == "u1")
        #expect(viewModel.cameraCommand?.sequence == sequenceAfterLoad)
        #expect(viewModel.region == regionAfterLoad)
    }

    @Test func selectingTheAlreadySelectedMember_deselects() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [self.member("u1", "Eric", devices: [self.device("d1", lat: 51.0, lon: 3.7)])]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        viewModel.selectMember("u1")
        #expect(viewModel.selectedUserId == "u1")

        viewModel.selectMember("u1")

        #expect(viewModel.selectedUserId == nil)
    }

    @Test func fitAll_alwaysMintsANewCameraCommand_regardlessOfPolicyState() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [self.member("u1", "Eric", devices: [self.device("d1", lat: 51.0, lon: 3.7)])]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        // Steady state: a second load (refresh) mints no new command.
        await viewModel.load()
        let steadySequence = viewModel.cameraCommand?.sequence

        viewModel.fitAll()

        #expect(viewModel.cameraCommand?.sequence != steadySequence)
        #expect(viewModel.cameraCommand?.target == .center(lat: 51.0, lon: 3.7, zoom: MapCameraPolicy.singlePointZoom))
    }

    @Test func aMemberWhoDisappearsFromTheRoster_isNoLongerSelected() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [self.member("u1", "Eric", devices: [self.device("d1", lat: 51.0, lon: 3.7)])]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()
        viewModel.selectMember("u1")
        #expect(viewModel.selectedUserId == "u1")

        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: []))
        }
        await viewModel.load()

        #expect(viewModel.selectedUserId == nil)
    }

    @Test func selectingAMember_marksOnlyTheirOwnAnnotationsSelected() async {
        let api = FakeAPIClient()
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                self.member("u1", "Eric", devices: [self.device("d1", lat: 51.0, lon: 3.7)]),
                self.member("u2", "Noor", devices: [self.device("d2", lat: 48.0, lon: 2.3)]),
            ]))
        }
        let viewModel = LiveMapViewModel(apiClient: api)
        await viewModel.load()

        viewModel.selectMember("u1")

        #expect(viewModel.annotations.first { $0.id == "d1" }?.isSelected == true)
        #expect(viewModel.annotations.first { $0.id == "d2" }?.isSelected == false)
    }
}
