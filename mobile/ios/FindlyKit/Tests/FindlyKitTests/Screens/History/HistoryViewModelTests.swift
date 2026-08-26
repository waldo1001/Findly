import Testing
@testable import FindlyKit

/// specs/004-ios-client.md I2 (001 §5.3) — date-range history with cursor pagination.
@MainActor
struct HistoryViewModelTests {

    func makePoint(_ recordedAt: String) -> HistoryPoint {
        HistoryPoint(deviceId: "d1", recordedAt: recordedAt, lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    @Test func initialState_isIdle() {
        let viewModel = HistoryViewModel(apiClient: FakeAPIClient(), userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")
        #expect(viewModel.state == .idle)
    }

    @Test func load_singlePage_hasMoreFalseWhenCursorIsNil() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            TestFeatures.envelope(LocationHistoryResponse(points: [self.makePoint("2026-07-19T09:00:00Z")], nextCursor: nil))
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")

        await viewModel.load()

        #expect(viewModel.state == .loaded(points: [makePoint("2026-07-19T09:00:00Z")], hasMore: false))
        #expect(api.getLocationHistoryCalls.count == 1)
        #expect(api.getLocationHistoryCalls.first?.cursor == nil)
    }

    @Test func loadMore_followsTheReturnedCursor_andAppendsPoints() async {
        let api = FakeAPIClient()
        var callIndex = 0
        api.getLocationHistoryHandler = { _, _, _, _, _, cursor in
            callIndex += 1
            if callIndex == 1 {
                #expect(cursor == nil)
                return TestFeatures.envelope(LocationHistoryResponse(points: [self.makePoint("2026-07-19T09:00:00Z")], nextCursor: "page2"))
            } else {
                #expect(cursor == "page2")
                return TestFeatures.envelope(LocationHistoryResponse(points: [self.makePoint("2026-07-19T10:00:00Z")], nextCursor: nil))
            }
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")

        await viewModel.load()
        #expect(viewModel.state == .loaded(points: [makePoint("2026-07-19T09:00:00Z")], hasMore: true))

        await viewModel.loadMore()

        #expect(viewModel.state == .loaded(points: [makePoint("2026-07-19T09:00:00Z"), makePoint("2026-07-19T10:00:00Z")], hasMore: false))
        #expect(api.getLocationHistoryCalls.count == 2)
    }

    @Test func loadMore_isNoOp_whenNoMorePagesRemain() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            TestFeatures.envelope(LocationHistoryResponse(points: [], nextCursor: nil))
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")

        await viewModel.load()
        await viewModel.loadMore()

        #expect(api.getLocationHistoryCalls.count == 1, "loadMore must not call the API once hasMore is false")
    }

    @Test func load_resetsPagination_onASecondFreshLoad() async {
        let api = FakeAPIClient()
        var callIndex = 0
        api.getLocationHistoryHandler = { _, _, _, _, _, cursor in
            callIndex += 1
            if callIndex == 1 {
                return TestFeatures.envelope(LocationHistoryResponse(points: [self.makePoint("2026-07-19T09:00:00Z")], nextCursor: "page2"))
            } else {
                // The second top-level load() must start over with cursor: nil, not resume page2.
                #expect(cursor == nil)
                return TestFeatures.envelope(LocationHistoryResponse(points: [self.makePoint("2026-08-01T09:00:00Z")], nextCursor: nil))
            }
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")
        await viewModel.load()

        viewModel.fromDate = "2026-08-01"
        viewModel.toDate = "2026-08-01"
        await viewModel.load()

        #expect(viewModel.state == .loaded(points: [makePoint("2026-08-01T09:00:00Z")], hasMore: false))
    }

    @Test func load_failure_setsErrorState() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            throw APIError.server(APIErrorBody(code: .validationFailed, message: "beyond retention", details: nil, requestId: "r1"), httpStatus: 400)
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2020-01-01", toDate: "2020-01-31")

        await viewModel.load()

        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    // MARK: - specs/001 §5.3 max 31-day span (client-side pre-check, review-gate finding #1)

    @Test func load_dateRangeExactly31Days_isAllowed() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            TestFeatures.envelope(LocationHistoryResponse(points: [], nextCursor: nil))
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-31")

        await viewModel.load()

        #expect(api.getLocationHistoryCalls.count == 1)
        #expect(viewModel.state == .loaded(points: [], hasMore: false))
    }

    @Test func load_dateRangeOver31Days_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            TestFeatures.envelope(LocationHistoryResponse(points: [], nextCursor: nil))
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-08-02")

        await viewModel.load()

        #expect(api.getLocationHistoryCalls.isEmpty, "a >31-day span must never reach the network")
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func load_reversedDateRange_isRejectedWithoutCallingTheApi() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            TestFeatures.envelope(LocationHistoryResponse(points: [], nextCursor: nil))
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-19", toDate: "2026-07-01")

        await viewModel.load()

        #expect(api.getLocationHistoryCalls.isEmpty)
        guard case .error = viewModel.state else {
            Issue.record("expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func fromDate_and_toDate_arePublished_forDatePickerBinding() async {
        // review-gate finding #1 — the screen binds a DatePicker directly to these; they must be
        // independently settable and reflected immediately (no separate "commit" step).
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            TestFeatures.envelope(LocationHistoryResponse(points: [], nextCursor: nil))
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")

        viewModel.fromDate = "2026-07-10"
        viewModel.toDate = "2026-07-20"

        #expect(viewModel.fromDate == "2026-07-10")
        #expect(viewModel.toDate == "2026-07-20")
    }

    // MARK: - specs/010-app-shell-and-screen-ux.md §2.1 (I34) — the profile-dead-end routing rule.
    // `GET /locations/history` is family-scoped (001 §5.3/§1.5.4).

    @Test func load_profileNotFound_routesToOnboardingProfileLess() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            throw APIError.server(APIErrorBody(code: .profileNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.profileLess))
    }

    @Test func load_familyNotFound_routesToOnboardingFamilyLess() async {
        let api = FakeAPIClient()
        api.getLocationHistoryHandler = { _, _, _, _, _, _ in
            throw APIError.server(APIErrorBody(code: .familyNotFound, message: "x", details: nil, requestId: "r1"), httpStatus: 404)
        }
        let viewModel = HistoryViewModel(apiClient: api, userId: "u1", fromDate: "2026-07-01", toDate: "2026-07-19")

        await viewModel.load()

        #expect(viewModel.state == .routeToOnboarding(.familyLess))
    }
}
