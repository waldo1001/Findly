import Foundation
import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §8.1, specs/009-device-runtime.md §5.1 — `LOCATE_REQUEST` handling.
/// Deliberately takes no pause/tracking-enabled input at all (matches Android's
/// `LocateRequestPushHandler` doc): a paused device still fulfills an explicit locate request:
/// only the periodic pipeline's own suppression rules (`FixCaptureCoordinator`) check pause state,
/// and this class bypasses that coordinator entirely by calling `LocationProviding` directly.
struct LocateRequestPushHandlerTests {

    private static let iso = ISO8601DateFormatter()

    private func makeHandler(
        location: FakeLocationProviding,
        api: FakeAPIClient,
        deviceId: String? = "device-1",
        now: Date
    ) -> LocateRequestPushHandler {
        LocateRequestPushHandler(locationProvider: location, apiClient: api, deviceId: { deviceId }, now: { now })
    }

    private func fix() -> LocationFix {
        LocationFix(fixId: "fix-1", recordedAt: "2026-07-19T09:05:00Z", lat: 51.05, lon: 3.71, accuracyM: 4.8, batteryPct: 90, source: .locate)
    }

    @Test func withinWindow_capturesHighAccuracyFixAndFulfills() async throws {
        let location = FakeLocationProviding()
        location.nextFix = .success(fix())
        let api = FakeAPIClient()
        api.fulfillLocateRequestHandler = { _, _, _ in TestFeatures.envelope(FulfillLocateRequestResponse(status: "fulfilled")) }
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["requestId": "lr_1", "expiresAt": "2026-07-19T09:06:12Z", "requestedByName": "Eric"])

        #expect(location.requestSingleFixCalls == [.locate])
        #expect(api.fulfillLocateRequestCalls.count == 1)
        let call = try #require(api.fulfillLocateRequestCalls.first)
        #expect(call.deviceId == "device-1")
        #expect(call.requestId == "lr_1")
        #expect(call.fix.source == .locate)
    }

    @Test func pastExpiresAtPlusTenMinutes_isIgnored_noGPSBurn() async {
        let location = FakeLocationProviding()
        let api = FakeAPIClient()
        // expiresAt 09:06:12 + 10m grace = 09:16:12; one second past that is stale.
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:16:13Z")!)

        await handler.handle(["requestId": "lr_1", "expiresAt": "2026-07-19T09:06:12Z"])

        #expect(location.requestSingleFixCalls.isEmpty)
        #expect(api.fulfillLocateRequestCalls.isEmpty)
    }

    @Test func exactlyAtTheGraceBoundary_isStillFulfilled() async {
        let location = FakeLocationProviding()
        location.nextFix = .success(fix())
        let api = FakeAPIClient()
        api.fulfillLocateRequestHandler = { _, _, _ in TestFeatures.envelope(FulfillLocateRequestResponse(status: "fulfilled")) }
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:16:12Z")!)

        await handler.handle(["requestId": "lr_1", "expiresAt": "2026-07-19T09:06:12Z"])

        #expect(api.fulfillLocateRequestCalls.count == 1)
    }

    @Test func missingRequestId_isDroppedSilently() async {
        let location = FakeLocationProviding()
        let api = FakeAPIClient()
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["expiresAt": "2026-07-19T09:06:12Z"])

        #expect(location.requestSingleFixCalls.isEmpty)
        #expect(api.fulfillLocateRequestCalls.isEmpty)
    }

    @Test func blankRequestId_isDroppedSilently() async {
        let location = FakeLocationProviding()
        let api = FakeAPIClient()
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["requestId": "", "expiresAt": "2026-07-19T09:06:12Z"])

        #expect(location.requestSingleFixCalls.isEmpty)
    }

    @Test func malformedExpiresAt_isDroppedSilently_neverCrashes() async {
        let location = FakeLocationProviding()
        let api = FakeAPIClient()
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["requestId": "lr_1", "expiresAt": "not-a-date"])

        #expect(location.requestSingleFixCalls.isEmpty)
        #expect(api.fulfillLocateRequestCalls.isEmpty)
    }

    @Test func missingExpiresAt_isDroppedSilently() async {
        let location = FakeLocationProviding()
        let api = FakeAPIClient()
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["requestId": "lr_1"])

        #expect(location.requestSingleFixCalls.isEmpty)
    }

    @Test func noDeviceIdToFulfillAs_isDroppedSilently_neverCrashes() async {
        let location = FakeLocationProviding()
        let api = FakeAPIClient()
        let handler = makeHandler(location: location, api: api, deviceId: nil, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["requestId": "lr_1", "expiresAt": "2026-07-19T09:06:12Z"])

        #expect(location.requestSingleFixCalls.isEmpty, "no GPS burn when there's no device to fulfill as")
        #expect(api.fulfillLocateRequestCalls.isEmpty)
    }

    @Test func fixCaptureFails_givesUpSilently_noFulfillCall() async {
        let location = FakeLocationProviding()
        location.nextFix = .failure(LocationProvidingError.timedOut)
        let api = FakeAPIClient()
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        await handler.handle(["requestId": "lr_1", "expiresAt": "2026-07-19T09:06:12Z"])

        #expect(api.fulfillLocateRequestCalls.isEmpty)
    }

    @Test func fulfillCallFails_neverThrows() async {
        let location = FakeLocationProviding()
        location.nextFix = .success(fix())
        let api = FakeAPIClient()
        api.fulfillLocateRequestHandler = { _, _, _ in throw APIError.transport("offline") }
        let handler = makeHandler(location: location, api: api, now: Self.iso.date(from: "2026-07-19T09:05:00Z")!)

        // Must not throw - the requester's own poll surfaces the outcome (specs/009 §5.1).
        await handler.handle(["requestId": "lr_1", "expiresAt": "2026-07-19T09:06:12Z"])
    }
}
