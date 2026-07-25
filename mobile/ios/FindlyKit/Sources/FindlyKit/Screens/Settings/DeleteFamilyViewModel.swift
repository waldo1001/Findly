import Foundation

/// specs/004-ios-client.md §3.6, specs/008-privacy-endpoints.md §5 — family deletion. Parent-only
/// (the server enforces the role check, `403 AUTH_FORBIDDEN` for anyone else — this view model
/// doesn't pre-emptively gate on role; `PrivacySettingsViewModel` decides whether the entry is even
/// shown). On `204` the caller's own account survives, family-less (008 §5.2) — `Screen`s route
/// back to Home, which already renders the family-less state via `FAMILY_NOT_FOUND` (`HomeViewModel`).
@MainActor
public final class DeleteFamilyViewModel: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case ready(familyName: String)
        case deleting
        case completed
        case error(String)
    }

    @Published public private(set) var phase: Phase = .loading

    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        phase = .loading
        do {
            let envelope = try await apiClient.getMyFamily()
            phase = .ready(familyName: envelope.data.familyName)
        } catch {
            phase = .error(userFacingMessage(for: error))
        }
    }

    public func confirmDelete() async {
        phase = .deleting
        do {
            try await apiClient.deleteFamily()
            phase = .completed
        } catch {
            phase = .error(userFacingMessage(for: error))
        }
    }

    /// specs/008-privacy-endpoints.md §5.4 — names the irreversible loss of the WHOLE family's
    /// history, for every member, not just the caller's own.
    public static func confirmationMessage(familyName: String) -> String {
        "Delete \"\(familyName)\" for everyone? This permanently erases the family's shared history, geofences, and every member's location history. This can't be undone."
    }
}
