import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §6) — create → poll-every-2s-until-terminal. Uses an injected,
/// externally-releasable `sleep` so the poll loop advances deterministically instead of racing a
/// real 2 s timer.
@MainActor
struct LocateViewModelTests {

    @Test func requestLocate_pending_startsPolling_andStopsAtFulfilled() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_1", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                expiresAt: "2026-07-19T09:06:12Z", lastKnown: LastKnownFix(deviceId: "d2", lat: 51.0, lon: 3.7, accuracyM: 10, recordedAt: "2026-07-19T08:50:00Z")
            ))
        }
        var pollCount = 0
        api.pollLocateRequestHandler = { _ in
            pollCount += 1
            if pollCount < 2 {
                return TestFeatures.envelope(PollLocateRequestResponse(requestId: "lr_1", status: .pending, expiresAt: "2026-07-19T09:06:12Z", fix: nil))
            }
            return TestFeatures.envelope(PollLocateRequestResponse(
                requestId: "lr_1", status: .fulfilled, expiresAt: "2026-07-19T09:06:12Z",
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
        #expect(viewModel.fulfilledFix?.lat == 51.0544)

        // Terminal — a further release must not trigger any additional poll.
        await gate.release()
        try await Task.sleep(for: .milliseconds(20))
        #expect(api.pollLocateRequestCalls.count == 2)
    }

    @Test func requestLocate_immediatePushFailed_neverStartsPolling() async {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_2", status: .pushFailed, targetUserId: "u2", targetDeviceId: "d2",
                expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        let viewModel = LocateViewModel(apiClient: api, sleep: { _ in Issue.record("sleep must not be called") })

        await viewModel.requestLocate(target: .user("u2"))

        #expect(viewModel.status == .pushFailed)
        #expect(api.pollLocateRequestCalls.isEmpty)
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

    @Test func cancel_stopsThePollLoop_beforeItMakesAnotherCall() async throws {
        let api = FakeAPIClient()
        api.createLocateRequestHandler = { _ in
            TestFeatures.envelope(CreateLocateRequestResponse(
                requestId: "lr_3", status: .pending, targetUserId: "u2", targetDeviceId: "d2",
                expiresAt: "2026-07-19T09:06:12Z", lastKnown: nil
            ))
        }
        api.pollLocateRequestHandler = { _ in
            TestFeatures.envelope(PollLocateRequestResponse(requestId: "lr_3", status: .pending, expiresAt: "2026-07-19T09:06:12Z", fix: nil))
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
