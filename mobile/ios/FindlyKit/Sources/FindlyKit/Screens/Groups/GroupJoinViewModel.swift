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

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    /// `rawCode` may be a pasted code OR a full deep link (`findly://group-join?code=<code>`).
    /// `displayName` becomes the caller's per-group nickname (005 §1) if given; sent as `nil`
    /// (never an empty string) when blank.
    public func join(rawCode: String, displayName: String) async {
        guard let code = GroupCodeParsing.normalize(rawCode) else {
            state = .error("That group code doesn't look right. Double-check it and try again.")
            return
        }
        state = .joining
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let envelope = try await apiClient.joinGroup(code: code, displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName)
            state = .joined(envelope.data)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }
}
