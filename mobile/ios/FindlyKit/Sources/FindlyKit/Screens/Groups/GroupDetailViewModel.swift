import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.3–12.9; 005 §2.3) — group detail: roster + share code,
/// owner controls (rename/extend/end/rotate/kick/delete), and member self-service (leave).
///
/// `GROUP_EXPIRED` surfacing from ANY call here (load or mutation) sets `state = .expired` — a
/// persistent, rendered notice (same pattern as `GroupMapViewModel`), NOT an immediate silent exit
/// via `exitReason`. 005 §2.3's lazy-enforcement matrix means the group underneath this screen just
/// stopped being viewable; the spec (003 §12.2, mirrored by 004 §3.4) requires bouncing back to the
/// groups list "with a 'this group has ended' notice" — so the screen must actually show that
/// notice and let the caller acknowledge it (tap "Back to groups"), rather than the screen
/// vanishing out from under them before they can read anything.
@MainActor
public final class GroupDetailViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded(GroupDetail)
        case error(String)
        case expired
    }

    /// Terminal reasons for the screen to auto-navigate away. Both are the caller's OWN action
    /// succeeding — an immediate exit is the correct, expected UX there (unlike the surprise
    /// external `GROUP_EXPIRED` event, which is `state = .expired` instead, see above).
    public enum ExitReason: Equatable {
        case left
        case deleted
    }

    @Published public private(set) var state: State = .loading
    @Published public private(set) var lastActionError: String?
    @Published public private(set) var exitReason: ExitReason?

    private let apiClient: FindlyAPIClient
    public let groupId: String

    public init(apiClient: FindlyAPIClient, groupId: String) {
        self.apiClient = apiClient
        self.groupId = groupId
    }

    public var isOwner: Bool {
        if case .loaded(let detail) = state { return detail.role == "owner" }
        return false
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getGroup(groupId: groupId)
            state = .loaded(envelope.data)
        } catch {
            if (error as? APIError)?.serverCode == .groupExpired {
                state = .expired
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    /// Owner-only (001 §12.4) — `endsAt` untouched.
    public func rename(name: String) async {
        await mutateSummary { client in
            try await client.updateGroup(groupId: self.groupId, name: name, endsAt: nil)
        }
    }

    /// Owner-only (001 §12.4). Extending a `grace`-state (`ended`) group reactivates it (005 §2.2).
    public func extend(endsAt: Date) async {
        await mutateSummary { client in
            try await client.updateGroup(groupId: self.groupId, name: nil, endsAt: Self.iso8601Formatter.string(from: endsAt))
        }
    }

    /// Owner-only convenience — `endsAt <= now + 5 min` means "end the group now" (001 §12.4).
    public func endNow() async {
        await mutateSummary { client in
            try await client.updateGroup(groupId: self.groupId, name: nil, endsAt: Self.iso8601Formatter.string(from: Date()))
        }
    }

    /// Owner-only (001 §12.7) — the old code stops working instantly.
    public func rotateCode() async {
        guard case .loaded(let detail) = state else { return }
        do {
            let response = try await apiClient.rotateGroupCode(groupId: groupId)
            state = .loaded(detail.withCode(response.data.code))
            lastActionError = nil
        } catch {
            handleMutationFailure(error)
        }
    }

    /// Owner-only (001 §12.9) — removes `userId`'s membership and their group-map position
    /// immediately.
    public func kick(userId: String) async {
        guard case .loaded(let detail) = state, let members = detail.members else { return }
        do {
            try await apiClient.removeGroupMember(groupId: groupId, userId: userId)
            let remaining = members.filter { $0.userId != userId }
            state = .loaded(detail.withMembers(remaining, memberCount: detail.memberCount - 1))
            lastActionError = nil
        } catch {
            handleMutationFailure(error)
        }
    }

    /// Any member, any non-expired state (005 §2.3) — the owner cannot leave (`VALIDATION_FAILED`,
    /// `details.reason: "ownerCannotLeave"`, 001 §12.8), surfaced as `lastActionError` like any
    /// other mutation rejection, not as an exit.
    public func leave() async {
        do {
            try await apiClient.leaveGroup(groupId: groupId)
            exitReason = .left
        } catch {
            handleMutationFailure(error)
        }
    }

    /// Owner-only (001 §12.5) — immediate, synchronous hard delete regardless of state/policy.
    public func deleteGroup() async {
        do {
            try await apiClient.deleteGroup(groupId: groupId)
            exitReason = .deleted
        } catch {
            handleMutationFailure(error)
        }
    }

    /// Shared plumbing for the two PATCH-shaped mutations (`rename`/`extend`/`endNow`), which
    /// return a §12.2 summary shape — the roster/`createdAt` (not part of that shape) are carried
    /// forward from the currently-loaded detail rather than discarded.
    private func mutateSummary(_ operation: (FindlyAPIClient) async throws -> Envelope<GroupSummary>) async {
        guard case .loaded(let detail) = state else { return }
        do {
            let updated = try await operation(apiClient).data
            state = .loaded(detail.updatingSummary(updated))
            lastActionError = nil
        } catch {
            handleMutationFailure(error)
        }
    }

    private func handleMutationFailure(_ error: Error) {
        if (error as? APIError)?.serverCode == .groupExpired {
            state = .expired
        } else {
            lastActionError = userFacingMessage(for: error)
        }
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    /// The bare templated sentence (specs/007-public-join-links.md §4's group template, first
    /// line only) — reproduced byte-for-byte, NOT paraphrased: `Join my "{group name}" group on
    /// Findly — code {CODE}`, where the dash is an em dash (U+2014) and `{CODE}` is CANONICAL
    /// (uppercase, no hyphen) — unlike the family-invite template, which hyphenates its display
    /// code (`CreateInviteViewModel.displayForm`). This is the exact text `GroupDetailScreen`
    /// renders in-card next to the share button; `shareText(for:groupName:joinLinkHost:)` below
    /// is this sentence PLUS the §1 link, and is what actually reaches the share sheet (I42).
    public static func shareText(for code: String, groupName: String) -> String {
        "Join my \"\(groupName)\" group on Findly \u{2014} code \(code.uppercased())"
    }

    /// I42 (specs/007-public-join-links.md §4) — the full `ShareLink` payload: the sentence above,
    /// a newline, then the §1 `https://{joinLinkHost}/g#CODE` link — matching the template
    /// byte-for-byte (it also matches the already-shipped Android text, which 007 §4 pins as the
    /// cross-platform contract). Deliberately no store URL (007 §4: "the message stays short").
    /// Built from `joinLink(for:joinLinkHost:)` (not string interpolation) so the code stays
    /// provably fragment-only here too.
    public static func shareText(for code: String, groupName: String, joinLinkHost: String) -> String {
        let link = joinLink(for: code, joinLinkHost: joinLinkHost)
        return "\(shareText(for: code, groupName: groupName))\n\(link.absoluteString)"
    }

    /// specs/007-public-join-links.md §1, specs/004-ios-client.md §3.5 — the canonical
    /// `https://{joinLinkHost}/g#CODE` link: this is what the detail screen's `ShareLink` now
    /// shares and what its on-device QR encodes ("the https form is the canonical one for sharing
    /// and QR", 007 §1). Built via `URLComponents` (not string interpolation) so the code is
    /// provably set through the **fragment** property, never the path or query — the load-bearing
    /// privacy property that keeps the join capability out of every server/CDN log by construction.
    public static func joinLink(for code: String, joinLinkHost: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = joinLinkHost
        components.path = "/g"
        components.fragment = code.uppercased()
        return components.url!
    }
}

private extension GroupDetail {
    func withCode(_ newCode: String) -> GroupDetail {
        GroupDetail(
            groupId: groupId, name: name, endsAt: endsAt, expiryPolicy: expiryPolicy, state: state,
            role: role, memberCount: memberCount, code: newCode, createdAt: createdAt, members: members
        )
    }

    func withMembers(_ newMembers: [GroupMember], memberCount newMemberCount: Int) -> GroupDetail {
        GroupDetail(
            groupId: groupId, name: name, endsAt: endsAt, expiryPolicy: expiryPolicy, state: state,
            role: role, memberCount: newMemberCount, code: code, createdAt: createdAt, members: newMembers
        )
    }

    /// Merges a §12.2 summary response (create/update/join shape — no roster/`createdAt`) into
    /// this detail, preserving the fields the summary doesn't carry.
    func updatingSummary(_ summary: GroupSummary) -> GroupDetail {
        GroupDetail(
            groupId: summary.groupId, name: summary.name, endsAt: summary.endsAt,
            expiryPolicy: summary.expiryPolicy, state: summary.state, role: summary.role,
            memberCount: summary.memberCount, code: summary.code, createdAt: createdAt, members: members
        )
    }
}
