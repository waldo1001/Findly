import Foundation

/// specs/004-ios-client.md §3.6, specs/003-android-client.md §12.4 — the privacy settings hub:
/// Export (all users; parents may additionally export a member) / Delete account (all users —
/// MUST be reachable without contacting support, a store requirement) / Delete family (parents
/// only). This view model exists purely to gate the "Delete family" entry on `isParent`; Export and
/// Delete-account entries are unconditionally shown regardless of `state`.
@MainActor
public final class PrivacySettingsViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(isParent: Bool)
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
            let envelope = try await apiClient.getMyFamily()
            state = .loaded(isParent: envelope.data.me.role == "parent")
        } catch {
            if let code = (error as? APIError)?.serverCode, code == .familyNotFound || code == .profileNotFound {
                state = .loaded(isParent: false)
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }
}
