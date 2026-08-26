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
}
