import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §1.1 — the async orchestrator: runs the `GET /families/me`
/// probe (never for a signed-out caller), classifies its outcome, and defers to `LaunchGate` for
/// the actual routing decision. Also the one place `FamilyContextCache` gets populated from a
/// successful probe (§1.2).
@MainActor
struct AppLaunchResolverTests {

    @Test func notSignedIn_neverCallsTheProbe() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { fatalError("must not be called") }

        let destination = await AppLaunchResolver.resolve(apiClient: api, isSignedIn: false)

        #expect(destination == .signIn)
        #expect(api.getMyFamilyCallCount == 0)
    }

    @Test func signedIn_confirmedProfileAndFamily_routesToFamilyMapAndPopulatesCache() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"),
                members: [
                    FamilyMember(userId: "u1", role: "parent", displayName: "Eric", joinedAt: "2026-07-19T08:00:00Z"),
                    FamilyMember(userId: "u2", role: "member", displayName: "Noor", joinedAt: "2026-07-19T08:01:00Z"),
                ]
            ))
        }
        let cache = FamilyContextCache()

        let destination = await AppLaunchResolver.resolve(apiClient: api, isSignedIn: true, cache: cache)

        #expect(destination == .familyMap)
        #expect(cache.familyName == "Wauters")
        #expect(cache.myDisplayName == "Eric")
        #expect(cache.isParent == true)
    }

    @Test func signedIn_confirmedNoProfile_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }

        let destination = await AppLaunchResolver.resolve(apiClient: api, isSignedIn: true)

        #expect(destination == .onboarding(.profileLess))
    }

    @Test func signedIn_confirmedNoFamily_routesToOnboardingFamilyLess() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }

        let destination = await AppLaunchResolver.resolve(apiClient: api, isSignedIn: true)

        #expect(destination == .onboarding(.familyLess))
    }

    /// The rule this whole thing exists to enforce: a transient failure must fail open, never
    /// stranding a valid user in onboarding.
    @Test func signedIn_transportFailure_failsOpenToFamilyMap() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }

        let destination = await AppLaunchResolver.resolve(apiClient: api, isSignedIn: true)

        #expect(destination == .familyMap)
    }

    @Test func signedIn_serverErrorOtherThanTheTwo404s_failsOpenToFamilyMap() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .internalError, message: "boom", details: nil, requestId: "r1"), httpStatus: 500)
        }

        let destination = await AppLaunchResolver.resolve(apiClient: api, isSignedIn: true)

        #expect(destination == .familyMap)
    }

    /// specs/010-app-shell-and-screen-ux.md §1.1 (amended, row A37) — `classify` is the one place
    /// the four confirmed-auth-failure codes (001 §10) map to `.confirmedAuthFailure`; every other
    /// server-carried code (tested above, `.internalError`) stays `.inconclusive`, unchanged.
    @Test func classify_confirmedAuthFailureCodes_returnsConfirmedAuthFailure() {
        let codes: [APIErrorCode] = [.authMissingToken, .authInvalidToken, .authTokenExpired, .authForbidden]
        for code in codes {
            let error = APIError.server(APIErrorBody(code: code, message: "x", details: nil, requestId: "r1"), httpStatus: 401)
            #expect(AppLaunchResolver.classify(error) == .confirmedAuthFailure, "\(code) must classify as confirmedAuthFailure")
        }
    }

    /// The rule this whole amendment exists to enforce: a confirmed auth failure MUST route to
    /// Sign-in AND clear the local session — never silently fail open the way an inconclusive probe
    /// does. `onConfirmedAuthFailure` is the seam `RootView` wires to the SAME wipe-then-sign-out
    /// shape `FindlyApp.swift`'s forced `onSignedOut` closure already uses.
    @Test func signedIn_confirmedAuthFailure_routesToSignInAndClearsTheSession() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .authTokenExpired, message: "expired", details: nil, requestId: "r1"), httpStatus: 401)
        }
        var clearSessionCallCount = 0

        let destination = await AppLaunchResolver.resolve(
            apiClient: api, isSignedIn: true, onConfirmedAuthFailure: { clearSessionCallCount += 1 }
        )

        #expect(destination == .signIn)
        #expect(clearSessionCallCount == 1)
    }

    /// Companion to the test above: an inconclusive probe (no decodable error code) MUST NOT clear
    /// the session — only a CONFIRMED auth failure does.
    @Test func signedIn_transportFailure_neverClearsTheSession() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = { throw APIError.transport("offline") }
        var clearSessionCallCount = 0

        let destination = await AppLaunchResolver.resolve(
            apiClient: api, isSignedIn: true, onConfirmedAuthFailure: { clearSessionCallCount += 1 }
        )

        #expect(destination == .familyMap)
        #expect(clearSessionCallCount == 0)
    }

    // MARK: - A37 review (Finding 1) — `resolveAfterSignIn` replaces RootView's three previously
    // unstructured `Task`s with one sequential function, so the post-sign-in triggers
    // (device registration, geofence sync) cannot observe a still-signed-in state
    // `onConfirmedAuthFailure` is concurrently tearing down. Table-driven the same way the rest of
    // this suite is: behavioral call-count assertions, not just the resulting destination.

    @Test func resolveAfterSignIn_confirmedAuthFailure_neverTriggersDeviceRegistrationOrGeofenceSync() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .authForbidden, message: "forbidden", details: nil, requestId: "r1"), httpStatus: 403)
        }
        var clearSessionCallCount = 0
        var deviceRegistrationCallCount = 0
        var geofenceSyncCallCount = 0

        let destination = await AppLaunchResolver.resolveAfterSignIn(
            apiClient: api,
            onConfirmedAuthFailure: { clearSessionCallCount += 1 },
            onDeviceRegistration: { deviceRegistrationCallCount += 1 },
            onGeofenceSync: { geofenceSyncCallCount += 1 }
        )

        #expect(destination == .signIn)
        #expect(clearSessionCallCount == 1)
        #expect(deviceRegistrationCallCount == 0, "a confirmed-unauthorized caller must never trigger POST /devices")
        #expect(geofenceSyncCallCount == 0, "a confirmed-unauthorized caller must never trigger the geofence config sync either")
    }

    @Test func resolveAfterSignIn_confirmedProfileAndFamily_triggersDeviceRegistrationThenGeofenceSync() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            TestFeatures.envelope(GetMyFamilyResponse(
                familyId: "fam_x", familyName: "Wauters", createdAt: "2026-07-19T08:00:00Z",
                me: MeSummary(userId: "u1", role: "parent"), members: []
            ))
        }
        var callOrder: [String] = []

        let destination = await AppLaunchResolver.resolveAfterSignIn(
            apiClient: api,
            onDeviceRegistration: { callOrder.append("device") },
            onGeofenceSync: { callOrder.append("geofence") }
        )

        #expect(destination == .familyMap)
        #expect(callOrder == ["device", "geofence"], "device registration and geofence sync must both run, in the same order RootView used to fire them")
    }

    /// Onboarding destinations are deliberately NOT gated by this function — only a confirmed auth
    /// failure is. `DeviceRegistrationService`'s own probe already no-ops correctly for a
    /// profile-less caller (A24); over-tightening this gate to cover onboarding too would silently
    /// resurrect that already-solved problem.
    @Test func resolveAfterSignIn_confirmedNoProfile_stillTriggersTheBootstrapRetryCallbacks() async {
        let api = FakeAPIClient()
        api.getMyFamilyHandler = {
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        var deviceRegistrationCallCount = 0

        let destination = await AppLaunchResolver.resolveAfterSignIn(
            apiClient: api, onDeviceRegistration: { deviceRegistrationCallCount += 1 }
        )

        #expect(destination == .onboarding(.profileLess))
        #expect(deviceRegistrationCallCount == 1)
    }
}
