import Foundation
import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §6) — create → poll-every-2s-until-terminal. Uses an injected,
/// externally-releasable `sleep` so the poll loop advances deterministically instead of racing a
/// real 2 s timer.
///
/// **specs/009-device-runtime.md §5.1 "Requester side" (amended 2026-09-06, I51, building on
/// B26/A39's Android precedent).** Polling now stops at a terminal status **or the local end of the
/// request window**, then performs one `GET /locations/latest` fallback before declaring the device
/// unreachable — mirroring `LocateStateHolder`'s Android shape (window derived from the server's own
/// `createdAt`/`expiresAt` pair so clock skew cancels, measured as locally-elapsed time; a
/// zero-length or unparsable window never expires locally; a `late` outcome requires a non-null
/// fix, not `recordedAt` alone).
@MainActor
struct LocateViewModelTests {

    @Test func requestLocate_pending_startsPolling_andStopsAtFresh() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:06:12Z",
                lastKnown: LastKnownFix(deviceId: "d2", lat: 51.0, lon: 3.7, accuracyM: 10, recordedAt: "2026-07-19T08:50:00Z")
            ))
        }
        var pollCount = 0
        api.pollLocateRequestHandler = { _ in
            pollCount += 1
            if pollCount < 2 {
                return TestFeatures.envelope(PollLocateRequestResponse(
                    requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                    expiresAt: "2026-07-19T09:06:12Z", fulfilledAt: nil, late: false, fix: nil
                ))
            }
            return TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .fulfilled, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:06:12Z", fulfilledAt: "2026-07-19T09:05:50Z", late: false,
                fix: FulfilledFix(deviceId: "d2", fixId: "f1", recordedAt: "2026-07-19T09:05:44Z", lat: 51.0544, lon: 3.7170, accuracyM: 4.8, altitudeM: nil, speedMps: nil, bearingDeg: nil, batteryPct: 77, source: .locate)
            ))
        }
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        #expect(viewModel.status == .pending)
        #expect(viewModel.lastKnown?.deviceId == "d2")
        #expect(api.pollLocateRequestCalls.isEmpty, "no poll must fire before the first sleep tick resolves")

        await gate.release()
        try await waitUntil { api.pollLocateRequestCalls.count == 1 }
        #expect(viewModel.status == .pending)

        await gate.release()
        try await waitUntil { viewModel.status == .fulfilled }
        #expect(viewModel.resolvedPosition?.lat == 51.0544)

        // Terminal — a further release must not trigger any additional poll.
        await gate.release()
        try await Task.sleep(for: .milliseconds(20))
        #expect(api.pollLocateRequestCalls.count == 2)
    }

    @Test func requestLocate_pollFulfilledLate_rendersLateWithPosition_noFallbackCall() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .fulfilled, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:06:12Z", fulfilledAt: "2026-07-19T09:15:00Z", late: true,
                fix: FulfilledFix(deviceId: "d2", fixId: "f1", recordedAt: "2026-07-19T09:14:55Z", lat: 51.05, lon: 3.71, accuracyM: 6.0, altitudeM: nil, speedMps: nil, bearingDeg: nil, batteryPct: 50, source: .locate)
            ))
        }
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        await gate.release()
        try await waitUntil { viewModel.status == .late }

        #expect(viewModel.resolvedPosition?.recordedAt == "2026-07-19T09:14:55Z")
        #expect(api.getLatestLocationsCallCount == 0, "the wire already gave a definitive late fulfil — no fallback needed")
    }

    /// I51 review fix (Minor, finding 4): the same rule A39's finding 13 established for the
    /// fallback path (outcome and usable fix must move in lockstep) applies to the wire path too —
    /// a `fulfilled` response with no `fix` must not render a meaningless "Live" chip with no
    /// position. It must fall through to the same fallback/unreachable decision as any other
    /// non-fresh terminal.
    @Test func requestLocate_pollFulfilledWithNullFix_fallsThroughToFallback_notFulfilledWithNoPosition() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .fulfilled, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:06:12Z", fulfilledAt: "2026-07-19T09:05:50Z", late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u2", displayName: "Noor", devices: [
                    DeviceLocation(deviceId: "d2", deviceName: "Noor's phone", lat: 51.06, lon: 3.72, accuracyM: 8.0, recordedAt: "2026-07-19T09:10:00Z", receivedAt: "2026-07-19T09:10:01Z", batteryPct: 40, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false)
                ])
            ]))
        }
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        await gate.release()
        try await waitUntil { viewModel.status != .pending }

        #expect(viewModel.status == .late, "a wire fulfilled with no fix must fall through to the fallback decision, not render a meaningless Live chip")
        #expect(viewModel.resolvedPosition?.lat == 51.06)
        #expect(api.getLatestLocationsCallCount == 1)
        #expect(viewModel.wireStatus == .fulfilled, "the wire answered with a real (if fixless) fulfilled status — wireStatus must carry that through as-is, not fabricate .expired as if the server never answered")
    }

    @Test func requestLocate_pollWindowElapses_fallbackFindsNewerPosition_rendersLate() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:05:16Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:05:16Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u2", displayName: "Noor", devices: [
                    DeviceLocation(deviceId: "d2", deviceName: "Noor's phone", lat: 51.06, lon: 3.72, accuracyM: 8.0, recordedAt: "2026-07-19T09:10:00Z", receivedAt: "2026-07-19T09:10:01Z", batteryPct: 40, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false)
                ])
            ]))
        }
        let clock = SteppingClock(start: parseDate("2026-07-19T09:05:12Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        clock.advance(by: 10) // past the 4s window
        await gate.release()
        try await waitUntil { viewModel.status == .late }

        #expect(api.getLatestLocationsCallCount == 1)
        #expect(viewModel.resolvedPosition?.lat == 51.06)
    }

    /// I51 review fix (Low, security, finding 6): `resolveViaFallback` filters the family-wide
    /// `/locations/latest` response to the target `deviceId` — but every other fallback test above
    /// supplies exactly one member with one matching device, so nothing would catch that filter
    /// being loosened (e.g. to "first device with a newer recordedAt" or "any device on the target
    /// member"). This pins cross-member AND cross-device isolation: a second family member with a
    /// much newer position, plus a second, non-target device on the TARGET's own member also with a
    /// newer position, must both be ignored — only the exact target device's own position may
    /// surface.
    @Test func requestLocate_fallbackFiltersByExactDeviceId_ignoresOtherMembersAndSiblingDevices() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:05:16Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:05:16Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                // A different family member entirely, with a much newer recordedAt — must never
                // leak into the target's own answer.
                MemberLocations(userId: "u3", displayName: "Ravi", devices: [
                    DeviceLocation(deviceId: "d3", deviceName: "Ravi's phone", lat: 52.0, lon: 4.0, accuracyM: 5.0, recordedAt: "2026-07-19T09:59:00Z", receivedAt: "2026-07-19T09:59:01Z", batteryPct: 90, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false)
                ]),
                // The target's own member, but a SECOND, non-target device on that same member —
                // also with a newer recordedAt than the actual target device below. Must not
                // surface either.
                MemberLocations(userId: "u2", displayName: "Noor", devices: [
                    DeviceLocation(deviceId: "d2-other", deviceName: "Noor's tablet", lat: 53.0, lon: 5.0, accuracyM: 5.0, recordedAt: "2026-07-19T09:58:00Z", receivedAt: "2026-07-19T09:58:01Z", batteryPct: 80, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false),
                    DeviceLocation(deviceId: "d2", deviceName: "Noor's phone", lat: 51.06, lon: 3.72, accuracyM: 8.0, recordedAt: "2026-07-19T09:10:00Z", receivedAt: "2026-07-19T09:10:01Z", batteryPct: 40, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false)
                ])
            ]))
        }
        let clock = SteppingClock(start: parseDate("2026-07-19T09:05:12Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        clock.advance(by: 10) // past the 4s window
        await gate.release()
        try await waitUntil { viewModel.status == .late }

        #expect(viewModel.resolvedPosition?.lat == 51.06, "only the target device's own position may surface, never another member's or a sibling device's newer position")
        #expect(viewModel.resolvedPosition?.recordedAt == "2026-07-19T09:10:00Z")
    }

    @Test func requestLocate_pollWindowElapses_fallbackFindsNoNewerPosition_rendersUnreachable() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:05:16Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:05:16Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            // recordedAt is OLDER than createdAt — not a newer answer.
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u2", displayName: "Noor", devices: [
                    DeviceLocation(deviceId: "d2", deviceName: "Noor's phone", lat: 51.0, lon: 3.7, accuracyM: 8.0, recordedAt: "2026-07-19T08:00:00Z", receivedAt: "2026-07-19T08:00:01Z", batteryPct: 40, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: true)
                ])
            ]))
        }
        let clock = SteppingClock(start: parseDate("2026-07-19T09:05:12Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        clock.advance(by: 10)
        await gate.release()
        try await waitUntil { viewModel.status == .unreachable }

        #expect(viewModel.resolvedPosition == nil)
    }

    /// A39's review (mirrored here): deciding `late` off `recordedAt` alone yields a "located" state
    /// with no coordinates — the screen would then silently backfill the stale `lastKnown` position
    /// under a fresh-looking chip. A non-null fix is required.
    @Test func requestLocate_fallbackFindsNewerRecordedAtButNoCoordinates_rendersUnreachable_notLate() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:05:16Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:05:16Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            // recordedAt IS newer than createdAt, but lat/lon are still null (001 §5.2 "no location
            // yet" shape) — must not be shown as an answer.
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u2", displayName: "Noor", devices: [
                    DeviceLocation(deviceId: "d2", deviceName: "Noor's phone", lat: nil, lon: nil, accuracyM: nil, recordedAt: "2026-07-19T09:10:00Z", receivedAt: nil, batteryPct: nil, source: nil, trackingEnabled: true, syncIntervalMinutes: 15, isStale: nil)
                ])
            ]))
        }
        let clock = SteppingClock(start: parseDate("2026-07-19T09:05:12Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        clock.advance(by: 10)
        await gate.release()
        try await waitUntil { viewModel.status == .unreachable }

        #expect(viewModel.resolvedPosition == nil)
    }

    /// A39's clock-skew fix, mirrored: the window is `Duration(createdAt, expiresAt)` — two server
    /// values, so a constant offset in the local clock cancels — measured as **locally elapsed**
    /// time since the request was received. A phone whose clock runs fast must not report
    /// unreachable on its very first poll tick just because its own `now()` reads past the server's
    /// `expiresAt`.
    @Test func requestLocate_clientClockRunsFast_doesNotExpireOnFirstTick_onlyAfterRealElapsedWindow() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:00Z", expiresAt: "2026-07-19T09:05:04Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:00Z",
                expiresAt: "2026-07-19T09:05:04Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: []))
        }
        // The phone's own clock is wildly ahead of the server (e.g. 4 years fast) — an absolute
        // `now() >= expiresAt` comparison would satisfy on tick one. Only the locally-elapsed delta
        // since the request was received may drive expiry.
        let clock = SteppingClock(start: parseDate("2030-01-01T00:00:00Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))

        clock.advance(by: 1) // 1 s of real elapsed time — window is 4 s, must not expire yet.
        await gate.release()
        try await waitUntil { api.pollLocateRequestCalls.count == 1 }
        #expect(viewModel.status == .pending)
        #expect(api.getLatestLocationsCallCount == 0)

        clock.advance(by: 4) // now 5 s of real elapsed time — past the 4 s window.
        await gate.release()
        try await waitUntil { viewModel.status == .unreachable }
        #expect(api.getLatestLocationsCallCount == 1)
    }

    /// A39's final round, mirrored: a zero-length or unparsable window is malformed data, not an
    /// already-expired request — it must never satisfy the local-elapsed check.
    @Test func requestLocate_zeroLengthWindow_neverExpiresLocally_onlyWireStatusEndsIt() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:00Z", expiresAt: "2026-07-19T09:05:00Z", lastKnown: nil
            ))
        }
        var pollCount = 0
        api.pollLocateRequestHandler = { _ in
            pollCount += 1
            return TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:00Z",
                expiresAt: "2026-07-19T09:05:00Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        let clock = SteppingClock(start: parseDate("2026-07-19T09:05:00Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))

        clock.advance(by: 999) // arbitrarily large local elapsed time
        await gate.release()
        try await waitUntil { api.pollLocateRequestCalls.count == 1 }
        #expect(viewModel.status == .pending, "a zero-length window must never be treated as instantly expired")
        #expect(api.getLatestLocationsCallCount == 0)

        viewModel.cancel()
    }

    @Test func requestLocate_immediatePushFailed_resolvesViaFallback_late() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_2", status: .pushFailed, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:00Z", expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: [
                MemberLocations(userId: "u2", displayName: "Noor", devices: [
                    DeviceLocation(deviceId: "d2", deviceName: "Noor's phone", lat: 51.0, lon: 3.7, accuracyM: 10, recordedAt: "2026-07-19T09:05:30Z", receivedAt: "2026-07-19T09:05:31Z", batteryPct: 60, source: .periodic, trackingEnabled: true, syncIntervalMinutes: 15, isStale: false)
                ])
            ]))
        }
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in Issue.record("sleep must not be called") })

        await viewModel.requestLocate(target: .user("u2"))

        #expect(viewModel.status == .late)
        #expect(api.pollLocateRequestCalls.isEmpty)
        #expect(api.getLatestLocationsCallCount == 1)
    }

    @Test func requestLocate_immediatePushFailed_noNewerPosition_resolvesUnreachable() async {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_2", status: .pushFailed, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:00Z", expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.getLatestLocationsHandler = { TestFeatures.envelope(LatestLocationsResponse(members: [])) }
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in Issue.record("sleep must not be called") })

        await viewModel.requestLocate(target: .user("u2"))

        #expect(viewModel.status == .unreachable)
        #expect(api.pollLocateRequestCalls.isEmpty)
    }

    // MARK: - I51 review fix (Blocking, finding 1): `.unreachable` must not collapse the
    // `pushFailed`/`expired` distinction — 001 §6.2 assigns "couldn't reach the device" copy
    // specifically to `pushFailed`, never to a request that was simply never answered. Mirrors
    // Android's `LocateStateHolder`, which keeps the raw wire status on its terminal state "for
    // the UI's own copy".

    @Test func requestLocate_immediatePushFailed_unreachable_carriesWireStatusPushFailed() async {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_2", status: .pushFailed, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:00Z", expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.getLatestLocationsHandler = { TestFeatures.envelope(LatestLocationsResponse(members: [])) }
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in Issue.record("sleep must not be called") })

        await viewModel.requestLocate(target: .user("u2"))

        #expect(viewModel.status == .unreachable)
        #expect(viewModel.wireStatus == .pushFailed, "the create-time pushFailed short-circuit must carry its wire status onto the view model, so the screen can render the 'couldn't reach the device' copy rather than 'request expired'")
    }

    @Test func requestLocate_pollWindowElapses_unreachable_defaultsWireStatusExpired() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:05:16Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:05:16Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        api.getLatestLocationsHandler = {
            TestFeatures.envelope(LatestLocationsResponse(members: []))
        }
        let clock = SteppingClock(start: parseDate("2026-07-19T09:05:12Z"))
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, now: clock.now, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        clock.advance(by: 10) // past the 4s window — the server never actually said "expired".
        await gate.release()
        try await waitUntil { viewModel.status == .unreachable }

        #expect(viewModel.wireStatus == .expired, "a local-window timeout with no wire-terminal status at all must default to .expired, not be confused with pushFailed's distinct copy")
    }

    @Test func requestLocate_createFailure_setsFailedStatus() async {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            throw APIError.server(APIErrorBody(code: .deviceNotFound, message: "no device", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = LocateViewModel(apiClient: api)

        await viewModel.requestLocate(target: .device("d9"))

        guard case .failed = viewModel.status else {
            Issue.record("expected .failed status, got \(viewModel.status)")
            return
        }
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §2.1 (I34) — the profile-dead-end routing rule.
    // `POST /locate-requests` is family-scoped (001 §6/§1.5.4); `requestLocate` IS this screen's
    // load path (there is no separate `load()` — it fires from the screen's own `.task`).

    @Test func requestLocate_profileNotFound_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = LocateViewModel(apiClient: api)

        await viewModel.requestLocate(target: .device("d9"))

        #expect(viewModel.status == .routeToOnboarding(.profileLess))
    }

    @Test func requestLocate_familyNotFound_routesToOnboardingFamilyLess() async {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = LocateViewModel(apiClient: api)

        await viewModel.requestLocate(target: .device("d9"))

        #expect(viewModel.status == .routeToOnboarding(.familyLess))
    }

    @Test func cancel_stopsThePollLoop_beforeItMakesAnotherCall() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_3", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                createdAt: "2026-07-19T09:05:12Z", expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_3", status: .pending, createdAt: "2026-07-19T09:05:12Z",
                expiresAt: "2026-07-19T09:06:12Z", fulfilledAt: nil, late: false, fix: nil
            ))
        }
        let gate = SleepGate()
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in await gate.wait() })

        await viewModel.requestLocate(target: .user("u2"))
        viewModel.cancel()
        await gate.release()

        try await Task.sleep(for: .milliseconds(20))
        #expect(api.pollLocateRequestCalls.isEmpty, "cancel() before the sleep resolves must prevent any further poll")
    }
}

private func parseDate(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

/// A test-only controllable clock: `now()` only changes when the test explicitly `advance`s it,
/// modelling "locally elapsed" wall-clock time independently of what the injected `sleep` gate does
/// (specs/009 §5.1 "Requester side" clock-skew rule — mirrors A39's Android `now: () -> Instant`).
final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        self.current = start
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

/// A test-only gate that lets a poll loop's injected `sleep` be released one step at a time,
/// instead of racing a real timer.
actor SleepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pendingReleases = 0

    func wait() async {
        if pendingReleases > 0 {
            pendingReleases -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            pendingReleases += 1
        }
    }
}
