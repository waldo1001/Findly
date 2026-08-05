import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.6) — join a group from a pasted code or a deep link. Every
/// input is normalized/validated by `GroupCodeParsing` BEFORE the network call (security checklist
/// §5 — deep-link inputs validated before use), mirroring `AcceptInviteViewModel`.
@MainActor
public final class GroupJoinViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case joining
        case joined(GroupSummary)
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    private let apiClient: FindlyAPIClient
    /// I17: `true` when this join is one of the four 001 §1.5.3 profile-bootstrap paths (the
    /// caller reached here from `HomeViewModel.State.profileless`) — 001 §12.6's `displayName` is
    /// REQUIRED then, optional otherwise. Defaults `false` so the ordinary (already-has-a-profile)
    /// entry point via `GroupsListScreen` keeps its existing "blank means absent" behavior.
    private let needsDisplayName: Bool

    public init(apiClient: FindlyAPIClient, needsDisplayName: Bool = false) {
        self.apiClient = apiClient
        self.needsDisplayName = needsDisplayName
    }

    /// `rawCode` may be a pasted code OR a full deep link (`findly://group-join?code=<code>`).
    /// `displayName` becomes the caller's per-group nickname (005 §1) if given; blank is gated
    /// client-side BEFORE any network call only when [needsDisplayName]; otherwise sent as `nil`
    /// (never an empty string) when blank.
    public func join(rawCode: String, displayName: String) async {
        guard let code = GroupCodeParsing.normalize(rawCode) else {
            state = .error("That group code doesn't look right. Double-check it and try again.")
            return
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsDisplayName && trimmedDisplayName.isEmpty {
            state = .error("Enter a display name.")
            return
        }
        state = .joining
        do {
            let envelope = try await apiClient.joinGroup(code: code, displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName)
            state = .joined(envelope.data)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }
}
