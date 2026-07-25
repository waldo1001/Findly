import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 — the shared error → user-facing-message mapping every I2 view model
/// relies on.
struct APIErrorUserMessageTests {

    @Test func serverError_mapsToACodeSpecificMessage() {
        let error = APIError.server(APIErrorBody(code: .geofenceVersionConflict, message: "raw debug text", details: nil, requestId: "r1"), httpStatus: 409)
        #expect(error.userFacingMessage.contains("Someone else"))
        #expect(!error.userFacingMessage.contains("raw debug text"), "the raw server message must never leak into the UI")
    }

    @Test func serverError_exposesTheDecodedCode() {
        let error = APIError.server(APIErrorBody(code: .limitExceeded, message: "x", details: nil, requestId: "r1"), httpStatus: 402)
        #expect(error.serverCode == .limitExceeded)
    }

    @Test func nonServerErrors_haveNoServerCode() {
        #expect(APIError.transport("offline").serverCode == nil)
        #expect(APIError.notModified.serverCode == nil)
        #expect(APIError.decoding("bad json").serverCode == nil)
    }

    @Test func unknownCode_stillProducesAGenericMessage() {
        let error = APIError.server(APIErrorBody(code: .unknown("SOMETHING_NEW"), message: "x", details: nil, requestId: "r1"), httpStatus: 500)
        #expect(!error.userFacingMessage.isEmpty)
    }

    /// specs/005-temporary-groups.md — the six group-era codes must each map to a distinct,
    /// non-empty, non-leaking user-facing message (same rule as every other code).
    @Test func groupEraCodes_eachProduceASpecificMessage() {
        let cases: [(APIErrorCode, contains: String)] = [
            (.profileNotFound, "profile"),
            (.groupNotFound, "group"),
            (.groupAlreadyMember, "group"),
            (.groupFull, "full"),
            (.groupExpired, "ended"),
            (.groupCodeInvalid, "code"),
        ]
        for (code, needle) in cases {
            let error = APIError.server(APIErrorBody(code: code, message: "raw debug text", details: nil, requestId: "r1"), httpStatus: 400)
            #expect(error.userFacingMessage.lowercased().contains(needle), "\(code) message should mention '\(needle)'")
            #expect(!error.userFacingMessage.contains("raw debug text"))
        }
    }

    @Test func nonAPIError_getsAGenericFallbackMessage() {
        struct SomeOtherError: Error {}
        #expect(userFacingMessage(for: SomeOtherError()) == "Something went wrong. Please try again.")
    }

    /// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §3 — `402 LIMIT_EXCEEDED` with
    /// `details.limit: "exportsPerDay"` gets a friendly, export-specific retry-tomorrow message,
    /// distinct from the generic plan-limit message every other `LIMIT_EXCEEDED` still gets.
    @Test func limitExceeded_exportsPerDay_getsAFriendlyExportSpecificMessage() {
        let error = APIError.server(
            APIErrorBody(code: .limitExceeded, message: "x", details: ["limit": .string("exportsPerDay")], requestId: "r1"),
            httpStatus: 402
        )
        #expect(error.userFacingMessage.lowercased().contains("export"))
        #expect(error.userFacingMessage.lowercased().contains("tomorrow"))
    }

    @Test func limitExceeded_otherLimits_keepTheGenericMessage() {
        let error = APIError.server(
            APIErrorBody(code: .limitExceeded, message: "x", details: ["limit": .string("maxDevices")], requestId: "r1"),
            httpStatus: 402
        )
        #expect(error.userFacingMessage == "You've reached a plan limit.")
    }

    @Test func limitExceeded_noDetails_keepsTheGenericMessage() {
        let error = APIError.server(APIErrorBody(code: .limitExceeded, message: "x", details: nil, requestId: "r1"), httpStatus: 402)
        #expect(error.userFacingMessage == "You've reached a plan limit.")
    }
}
