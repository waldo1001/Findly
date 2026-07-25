import Foundation

/// specs/004-ios-client.md I2 (001 §3.2, §3.5–3.6) — family roster + member management. `isParent`
/// is derived from the loaded `me.role` (never injected separately, so it can't drift from what
/// the server actually returned) and gates role changes / removal client-side, matching §1.6's
/// parent-only role table.
@MainActor
public final class FamilyMembersViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(familyName: String, me: MeSummary, members: [FamilyMember])
        case error(String)
    }

    @Published public private(set) var state: State = .loading
    @Published public private(set) var lastActionError: String?

    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public var isParent: Bool {
        guard case .loaded(_, let me, _) = state else { return false }
        return me.role == "parent"
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getMyFamily()
            state = .loaded(familyName: envelope.data.familyName, me: envelope.data.me, members: envelope.data.members)
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    public func updateRole(userId: String, role: String) async {
        await mutateMember(userId: userId) { client in
            try await client.updateMember(userId: userId, role: role, displayName: nil)
        }
    }

    public func rename(userId: String, displayName: String) async {
        await mutateMember(userId: userId) { client in
            try await client.updateMember(userId: userId, role: nil, displayName: displayName)
        }
    }

    /// specs/001 §3.6 — the last parent cannot remove themselves (`VALIDATION_FAILED`,
    /// `details.reason: "lastParent"`); surfaced generically via `lastActionError` like any other
    /// failed mutation, the list stays untouched on failure.
    public func remove(userId: String) async {
        guard isParent else {
            lastActionError = "Only a parent can remove a member."
            return
        }
        guard case .loaded(let familyName, let me, var members) = state else { return }
        do {
            try await apiClient.removeMember(userId: userId)
            members.removeAll { $0.userId == userId }
            state = .loaded(familyName: familyName, me: me, members: members)
            lastActionError = nil
        } catch {
            lastActionError = userFacingMessage(for: error)
        }
    }

    private func mutateMember(userId: String, _ operation: (FindlyAPIClient) async throws -> Envelope<FamilyMember>) async {
        guard isParent else {
            lastActionError = "Only a parent can change member settings."
            return
        }
        guard case .loaded(let familyName, let me, var members) = state else { return }
        do {
            let updated = try await operation(apiClient).data
            if let index = members.firstIndex(where: { $0.userId == userId }) {
                members[index] = updated
            }
            state = .loaded(familyName: familyName, me: me, members: members)
            lastActionError = nil
        } catch {
            lastActionError = userFacingMessage(for: error)
        }
    }
}
