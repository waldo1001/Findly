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

    /// specs/008-privacy-endpoints.md §4.4 (review finding #3) — the Screen's own entries, one per
    /// settings row.
    public enum PrivacySettingsEntry: Hashable {
        case export
        case deleteAccount
        case deleteFamily
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

    /// specs/008-privacy-endpoints.md §4.4 (review finding #3) — a pure, independently-testable
    /// mapping from `state` to which entries the Screen renders. Export and Delete-account are
    /// UNCONDITIONAL — present for `.loading` and `.error` exactly as for `.loaded`, since a
    /// `GET /families/me` failure (5xx, timeout, offline — anything the family-less handling in
    /// `load()` doesn't already downgrade to `.loaded(isParent: false)`) MUST NOT remove the only
    /// way to reach account deletion (a store requirement: reachable without contacting support).
    /// Delete-family is the one entry that genuinely depends on a confirmed `isParent` and is
    /// gated on `.loaded(isParent: true)` only.
    public var visibleEntries: Set<PrivacySettingsEntry> {
        var entries: Set<PrivacySettingsEntry> = [.export, .deleteAccount]
        if case .loaded(true) = state {
            entries.insert(.deleteFamily)
        }
        return entries
    }
}
