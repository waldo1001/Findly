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

    @Test func limitExceeded_unknownLimit_keepsTheGenericMessage() {
        let error = APIError.server(
            APIErrorBody(code: .limitExceeded, message: "x", details: ["limit": .string("someFutureLimit")], requestId: "r1"),
            httpStatus: 402
        )
        #expect(error.userFacingMessage == "You've reached a plan limit.")
    }

    private func limitError(_ limit: String) -> APIError {
        APIError.server(
            APIErrorBody(code: .limitExceeded, message: "raw debug text", details: ["limit": .string(limit)], requestId: "r1"),
            httpStatus: 402
        )
    }

    /// specs/005 §2.5 item 7 — verbatim; the generic "plan limit" copy MUST NOT be shown for a
    /// group limit (field report 2026-10-12).
    @Test func limitExceeded_maxOwnedGroups_005Item7Verbatim() {
        #expect(limitError("maxOwnedGroups").userFacingMessage == "You already have the maximum number of active groups you created. End or delete one first.")
    }

    @Test func limitExceeded_maxJoinedGroups_005Item7Verbatim() {
        #expect(limitError("maxJoinedGroups").userFacingMessage == "You're already in the maximum number of active groups you joined. Leave one first.")
    }

    @Test func limitExceeded_maxGroupDurationDays_005Item7Verbatim() {
        #expect(limitError("maxGroupDurationDays").userFacingMessage == "That end date is further out than your plan allows.")
    }

    /// Mirrors Android's `ApiErrorUserMessage.kt` per-limit copy (I66 scope).
    @Test func limitExceeded_otherPlanLimits_mirrorAndroidCopy() {
        #expect(limitError("maxDevices").userFacingMessage == "You've reached your device limit for this plan.")
        #expect(limitError("maxGeofences").userFacingMessage == "You've reached your geofence limit for this plan.")
        #expect(limitError("locateRequestsPerDay").userFacingMessage == "You've reached today's locate-request limit.")
        #expect(limitError("minSyncIntervalMinutes").userFacingMessage == "That sync interval isn't available on your plan.")
    }

    @Test func limitExceeded_noGroupLimit_everShowsTheGenericMessage() {
        for limit in ["maxOwnedGroups", "maxJoinedGroups", "maxGroupDurationDays"] {
            #expect(limitError(limit).userFacingMessage != "You've reached a plan limit.")
            #expect(!limitError(limit).userFacingMessage.contains("raw debug text"))
        }
    }

    @Test func limitExceeded_noDetails_keepsTheGenericMessage() {
        let error = APIError.server(APIErrorBody(code: .limitExceeded, message: "x", details: nil, requestId: "r1"), httpStatus: 402)
        #expect(error.userFacingMessage == "You've reached a plan limit.")
    }

    /// I17 review (belt-and-braces) — 001 §12.1/§12.6's create-group/join-group bootstrap path
    /// (`backend/src/domain/group/createGroup.ts`/`joinGroup.ts`) reports a missing `displayName`
    /// as `400 VALIDATION_FAILED`, `details.fields: ["displayName"]`. This does NOT substitute for
    /// `CreateGroupViewModel`/`GroupJoinViewModel`'s own client-side profile probe (which should
    /// catch this before the network call in practice) — it's a fallback for the case that probe
    /// was inconclusive and the blank name reached the server anyway.
    @Test func validationFailed_displayNameField_getsASpecificMessage() {
        let error = APIError.server(
            APIErrorBody(code: .validationFailed, message: "x", details: ["fields": .array([.string("displayName")])], requestId: "r1"),
            httpStatus: 400
        )
        #expect(error.userFacingMessage == "Enter a display name.")
    }

    @Test func validationFailed_otherFields_keepTheGenericMessage() {
        let error = APIError.server(
            APIErrorBody(code: .validationFailed, message: "x", details: ["fields": .array([.string("fixes[3].recordedAt")])], requestId: "r1"),
            httpStatus: 400
        )
        #expect(error.userFacingMessage == "Please check your input and try again.")
    }

    @Test func validationFailed_noDetails_keepsTheGenericMessage() {
        let error = APIError.server(APIErrorBody(code: .validationFailed, message: "x", details: nil, requestId: "r1"), httpStatus: 400)
        #expect(error.userFacingMessage == "Please check your input and try again.")
    }
}
