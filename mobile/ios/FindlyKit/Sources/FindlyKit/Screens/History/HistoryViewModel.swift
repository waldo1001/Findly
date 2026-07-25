import Foundation

/// specs/004-ios-client.md I2 (001 §5.3) — per-member/device history with date-range selection and
/// cursor pagination. A fresh `load()` resets pagination; `loadMore()` follows `nextCursor` until
/// the server signals exhaustion (`nextCursor == nil`).
@MainActor
public final class HistoryViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded(points: [HistoryPoint], hasMore: Bool)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var isLoadingMore = false
    /// `@Published` (not just `var`) so a `DatePicker` bound via the screen picks up programmatic
    /// changes and so changing either bound triggers the screen to re-render immediately.
    @Published public var fromDate: String
    @Published public var toDate: String

    public let userId: String
    public var deviceId: String?

    private let apiClient: FindlyAPIClient
    private let pageSize: Int
    private var nextCursor: String?
    private var loadedPoints: [HistoryPoint] = []

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    public init(apiClient: FindlyAPIClient, userId: String, deviceId: String? = nil, fromDate: String, toDate: String, pageSize: Int = 200) {
        self.apiClient = apiClient
        self.userId = userId
        self.deviceId = deviceId
        self.fromDate = fromDate
        self.toDate = toDate
        self.pageSize = pageSize
    }

    /// Fresh load for the current `userId`/`deviceId`/date range — always resets pagination, even
    /// if a previous load was mid-way through pages. specs/001 §5.3 caps the span at 31 days;
    /// enforced client-side first so an over-long range never even reaches the network — mirroring
    /// the server's own `VALIDATION_FAILED` rejection instead of wasting a round trip on it.
    public func load() async {
        guard !dateRangeExceedsMaxSpan() else {
            state = .error("The date range can't be more than 31 days. Please choose a shorter range.")
            return
        }
        state = .loading
        loadedPoints = []
        nextCursor = nil
        await fetchNextPage()
    }

    /// `true` when the range is malformed-but-parseable-as-reversed or spans more than 31 days.
    /// Dates that fail to parse at all are left to the server to reject — this is a client-side
    /// fast path, not a full validator.
    private func dateRangeExceedsMaxSpan() -> Bool {
        guard let from = Self.dateFormatter.date(from: fromDate), let to = Self.dateFormatter.date(from: toDate) else {
            return false
        }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: from, to: to).day ?? 0
        return days > 31 || days < 0
    }

    /// specs/001 §5.3 cursor pagination — a no-op if the previous page was exhausted, a load is
    /// already in flight, or `load()` hasn't successfully completed at least once.
    public func loadMore() async {
        guard case .loaded(_, let hasMore) = state, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchNextPage()
    }

    private func fetchNextPage() async {
        do {
            let envelope = try await apiClient.getLocationHistory(
                userId: userId, deviceId: deviceId, from: fromDate, to: toDate, limit: pageSize, cursor: nextCursor
            )
            loadedPoints.append(contentsOf: envelope.data.points)
            nextCursor = envelope.data.nextCursor
            state = .loaded(points: loadedPoints, hasMore: nextCursor != nil)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }
}
