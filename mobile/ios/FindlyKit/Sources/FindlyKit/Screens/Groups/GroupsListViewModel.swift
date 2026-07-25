import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.2) — the caller's groups (owned + joined), expired ones
/// already filtered out server-side. Also the screen a family-less signed-in user reaches as a
/// non-dead-end destination (005 §1.5) — an empty `[GroupSummary]` is a normal, renderable state,
/// not an error.
@MainActor
public final class GroupsListViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded([GroupSummary])
        case error(String)
    }

    @Published public private(set) var state: State = .loading
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.listGroups()
            state = .loaded(envelope.data.groups)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }
}
