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
    /// I17: `true` when this creation is one of the four 001 §1.5.3 profile-bootstrap paths (the
    /// caller reached here from `HomeViewModel.State.profileless`, not the ordinary
    /// `GroupsListScreen`) — 001 §12.1's `displayName` is REQUIRED then, optional otherwise.
    /// Defaults `false` so every pre-I17 call site (the ordinary, already-has-a-profile path)
    /// keeps its existing "blank means absent" behavior unchanged.
    private let needsDisplayName: Bool

    public init(apiClient: FindlyAPIClient, needsDisplayName: Bool = false) {
        self.apiClient = apiClient
        self.needsDisplayName = needsDisplayName
    }

    /// `displayName` becomes the caller's per-group nickname (005 §1); required-if-no-profile,
    /// optional otherwise (001 §12.1) — blank is gated client-side BEFORE any network call only
    /// when [needsDisplayName] (same "gate before any network call" convention as
    /// `CreateFamilyViewModel`/`AcceptInviteViewModel`); otherwise a blank value is sent as `nil`,
    /// never an empty string standing in for "absent".
    public func createGroup(name: String, endsAt: Date, expiryPolicy: GroupExpiryPolicy, displayName: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state = .error("Enter a name for the group.")
            return
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsDisplayName && trimmedDisplayName.isEmpty {
            state = .error("Enter a display name.")
            return
        }
        state = .creating
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
