import Testing
@testable import FindlyKit

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
        #expect(viewModel.region == MapRegion(centerLat: 51.0, centerLon: 3.7))
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
        // No annotation means no fix arrived, so the region must stay at its pre-load default.
        #expect(viewModel.region == .findlyDefault)
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
