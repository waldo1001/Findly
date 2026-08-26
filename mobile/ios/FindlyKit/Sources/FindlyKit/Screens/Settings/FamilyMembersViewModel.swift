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
        /// specs/010-app-shell-and-screen-ux.md §2.1 — a confirmed `PROFILE_NOT_FOUND`/
        /// `FAMILY_NOT_FOUND` on this load (`GET /families/me` is family-scoped, 001 §3.2/§1.5.4).
        case routeToOnboarding(OnboardingVariant)
    }

    @Published public private(set) var state: State = .loading
    @Published public private(set) var lastActionError: String?

    private let apiClient: FindlyAPIClient
    /// specs/010-app-shell-and-screen-ux.md §1.2 — this screen already fetches everything the
    /// drawer header needs, so a successful load opportunistically refreshes the cache rather than
    /// leaving it stale until the next cold start. `nil` (the default) is a legitimate choice for
    /// any caller that doesn't wire the drawer through this screen (e.g. existing tests).
    private let familyContextCache: FamilyContextCache?

    public init(apiClient: FindlyAPIClient, familyContextCache: FamilyContextCache? = nil) {
        self.apiClient = apiClient
        self.familyContextCache = familyContextCache
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
            let myDisplayName = envelope.data.members.first(where: { $0.userId == envelope.data.me.userId })?.displayName ?? ""
            familyContextCache?.update(
                familyName: envelope.data.familyName, myDisplayName: myDisplayName, isParent: envelope.data.me.role == "parent"
            )
        } catch {
            if let variant = onboardingRoutingOutcome(for: error) {
                state = .routeToOnboarding(variant)
            } else {
                state = .error(userFacingMessage(for: error))
            }
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
