import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §7.1–7.2) — ETag-aware load/save, incl. the `GEOFENCE_VERSION_
/// CONFLICT` re-fetch + merge-UX flow.
@MainActor
struct GeofencesViewModelTests {

    func makeGeofence(_ id: String = "gf_home") -> Geofence {
        Geofence(geofenceId: id, name: "Home", lat: 51.0, lon: 3.7, radiusM: 150, icon: "home", notifyOnEnter: true, notifyOnExit: true)
    }

    @Test func initialState_isLoading() {
        let viewModel = GeofencesViewModel(apiClient: FakeAPIClient())
        #expect(viewModel.state == .loading)
    }

    @Test func load_success_cachesETagForTheNextRequest() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { ifNoneMatch in
            #expect(ifNoneMatch == nil, "first load has no cached ETag yet")
            return .ok(GeofenceConfig(version: 4, geofences: [self.makeGeofence()]), etag: "\"0x1\"", features: TestFeatures.free)
        }
        let viewModel = GeofencesViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .loaded(geofences: [makeGeofence()], version: 4))

        // A second load must present the cached ETag as If-None-Match.
        api.getGeofencesHandler = { ifNoneMatch in
            #expect(ifNoneMatch == "\"0x1\"")
            return .notModified
        }
        await viewModel.load()
        #expect(viewModel.state == .loaded(geofences: [makeGeofence()], version: 4), "a 304 must leave state unchanged")
    }

    @Test func save_success_updatesStateAndClearsConflict() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: []), etag: "\"0\"", features: TestFeatures.free) }
        api.replaceGeofencesHandler = { geofences, ifMatch in
            #expect(ifMatch == "\"0\"")
            return (TestFeatures.envelope(GeofenceConfig(version: 2, geofences: geofences)), "\"0x2\"")
        }
        let viewModel = GeofencesViewModel(apiClient: api)
        await viewModel.load()

        await viewModel.save([makeGeofence()])

        #expect(viewModel.state == .loaded(geofences: [makeGeofence()], version: 2))
        #expect(viewModel.conflict == .none)
        #expect(api.replaceGeofencesCalls.count == 1)
    }

    @Test func save_withoutPriorLoad_failsWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        let viewModel = GeofencesViewModel(apiClient: api)

        await viewModel.save([makeGeofence()])

        #expect(api.replaceGeofencesCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func save_versionConflict_refetchesAndSurfacesServerCopy() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: [self.makeGeofence()]), etag: "\"0x1\"", features: TestFeatures.free) }
        let viewModel = GeofencesViewModel(apiClient: api)
        await viewModel.load()

        api.replaceGeofencesHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .geofenceVersionConflict, message: "stale", details: nil, requestId: "r1"), httpStatus: 409)
        }
        let serverCopy = [makeGeofence("gf_home"), makeGeofence("gf_school")]
        api.getGeofencesHandler = { ifNoneMatch in
            #expect(ifNoneMatch == nil, "conflict recovery must force a fresh copy, not rely on a cached ETag")
            return .ok(GeofenceConfig(version: 3, geofences: serverCopy), etag: "\"0x3\"", features: TestFeatures.free)
        }

        await viewModel.save([makeGeofence("gf_home")])

        #expect(viewModel.conflict == .versionConflict(serverGeofences: serverCopy, serverVersion: 3))

        // The re-fetched ETag must be usable for a subsequent save (proves it was actually cached).
        api.replaceGeofencesHandler = { geofences, ifMatch in
            #expect(ifMatch == "\"0x3\"")
            return (TestFeatures.envelope(GeofenceConfig(version: 4, geofences: geofences)), "\"0x4\"")
        }
        await viewModel.save(serverCopy)
        #expect(viewModel.state == .loaded(geofences: serverCopy, version: 4))
    }

    @Test func acceptServerVersion_adoptsTheConflictingCopyAndClearsConflict() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: [self.makeGeofence()]), etag: "\"0x1\"", features: TestFeatures.free) }
        let viewModel = GeofencesViewModel(apiClient: api)
        await viewModel.load()

        api.replaceGeofencesHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .geofenceVersionConflict, message: "stale", details: nil, requestId: "r1"), httpStatus: 409)
        }
        let serverCopy = [makeGeofence("gf_school")]
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 5, geofences: serverCopy), etag: "\"0x5\"", features: TestFeatures.free) }
        await viewModel.save([makeGeofence()])

        viewModel.acceptServerVersion()

        #expect(viewModel.state == .loaded(geofences: serverCopy, version: 5))
        #expect(viewModel.conflict == .none)
    }

    @Test func save_nonConflictError_setsErrorState() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: []), etag: "\"0\"", features: TestFeatures.free) }
        let viewModel = GeofencesViewModel(apiClient: api)
        await viewModel.load()

        api.replaceGeofencesHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .limitExceeded, message: "too many", details: nil, requestId: "r1"), httpStatus: 402)
        }
        await viewModel.save([makeGeofence(), makeGeofence("gf_2"), makeGeofence("gf_3")])

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
        #expect(viewModel.conflict == .none)
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §2.1 (I34) — the profile-dead-end routing rule.
    // `GET /geofences` is family-scoped (001 §7.1/§1.5.4): the reported field bug (010's own
    // motivating example) was exactly this screen showing a Retry-that-can-never-work card.

    @Test func load_profileNotFound_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = GeofencesViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.profileLess))
    }

    @Test func load_familyNotFound_routesToOnboardingFamilyLess() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = GeofencesViewModel(apiClient: api)

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.familyLess))
    }

    /// Mutation-path failures keep the existing inline error rendering (010 §2.1's third rule) —
    /// `save_nonConflictError_setsErrorState` above already covers a mutation error generically;
    /// this pins that a profile-dead-end code specifically, arriving from `save` rather than
    /// `load`, still renders inline rather than routing.
    @Test func save_profileNotFound_staysInlineRatherThanRouting() async {
        let api = FakeAPIClient()
        api.getGeofencesHandler = { _ in .ok(GeofenceConfig(version: 1, geofences: []), etag: "\"0\"", features: TestFeatures.free) }
        let viewModel = GeofencesViewModel(apiClient: api)
        await viewModel.load()

        api.replaceGeofencesHandler = { _, _ in
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        await viewModel.save([makeGeofence()])

        guard case .error = viewModel.state else {
            Issue.record("expected .error state (mutation paths are unaffected by 010 §2.1), got \(viewModel.state)")
            return
        }
    }
}
