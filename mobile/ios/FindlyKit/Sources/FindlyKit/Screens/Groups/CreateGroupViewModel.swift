import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.1; 005 §2.1) — creates a group. `endsAt`/`expiryPolicy`
/// bounds (≥ now+1h, ≤ `limits.maxGroupDurationDays`) are the server's job (001 §12.1) — not
/// duplicated here beyond what the picker UI needs for a sane default, matching this client's
/// established "server is the source of truth" convention (specs/004 §3.4).
@MainActor
public final class CreateGroupViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case creating
        case created(GroupSummary)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// `displayName` becomes the caller's per-group nickname (005 §1); required-if-no-profile,
    /// optional otherwise (001 §12.1) — this view model doesn't need to know which applies, it
    /// just never sends a blank string standing in for "absent".
    public func createGroup(name: String, endsAt: Date, expiryPolicy: GroupExpiryPolicy, displayName: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state = .error("Enter a name for the group.")
            return
        }
        state = .creating
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let envelope = try await apiClient.createGroup(
                name: trimmedName,
                endsAt: Self.iso8601Formatter.string(from: endsAt),
                expiryPolicy: expiryPolicy.rawValue,
                displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
            )
            state = .created(envelope.data)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    private static let iso8601Formatter = ISO8601DateFormatter()
}
