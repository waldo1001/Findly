import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §2.1 — the routing rule shared by every feature screen's
/// *load* path: a confirmed `PROFILE_NOT_FOUND` or `FAMILY_NOT_FOUND` must never render a retryable
/// error card (retrying a GET cannot create a profile) — it routes to the corresponding Onboarding
/// variant instead. One pure classifier, reused by every view model's `load()` catch block, so the
/// mapping itself is tested exactly once rather than seven times over.
struct ProfileDeadEndRoutingTests {

    @Test func profileNotFound_mapsToProfileLessVariant() {
        let error = APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        #expect(onboardingRoutingOutcome(for: error) == .profileLess)
    }

    @Test func familyNotFound_mapsToFamilyLessVariant() {
        let error = APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        #expect(onboardingRoutingOutcome(for: error) == .familyLess)
    }

    @Test func anyOtherServerError_doesNotRoute() {
        let error = APIError.server(APIErrorBody(code: .internalError, message: "x", details: nil, requestId: "r1"), httpStatus: 500)
        #expect(onboardingRoutingOutcome(for: error) == nil)
    }

    @Test func transportOrDecodingFailure_doesNotRoute() {
        #expect(onboardingRoutingOutcome(for: APIError.transport("offline")) == nil)
        #expect(onboardingRoutingOutcome(for: APIError.decoding("bad json")) == nil)
    }

    @Test func nonAPIError_doesNotRoute() {
        struct SomeOtherError: Error {}
        #expect(onboardingRoutingOutcome(for: SomeOtherError()) == nil)
    }
}
