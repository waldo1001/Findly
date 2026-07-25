import Foundation

// specs/001-api-contract.md §12 — groups (temporary) wire shapes; product model/lifecycle/privacy
// guarantees are normative in specs/005-temporary-groups.md.

/// §12.1 request. `displayName` is REQUIRED only when the caller has no profile yet (§1.5.3
/// bootstrap) — optional otherwise, defaulting server-side to the profile's own.
public struct CreateGroupRequest: Encodable, Equatable {
    public let name: String
    public let endsAt: String
    public let expiryPolicy: String
    public let displayName: String?
    public init(name: String, endsAt: String, expiryPolicy: String, displayName: String? = nil) {
        self.name = name
        self.endsAt = endsAt
        self.expiryPolicy = expiryPolicy
        self.displayName = displayName
    }
}

/// The §12.2 list-item shape, reused verbatim as the §12.1/§12.4/§12.6 response (create/update/
/// join — specs/004-ios-client.md §3.2's mapping table). `createdAt` is present only on create
/// (§12.1); `nil` on the update/join/list responses. `code` is `nil` once the group is past
/// `endsAt` (005 §2.3 — the join-code row is deleted).
public struct GroupSummary: Decodable, Equatable {
    public let groupId: String
    public let name: String
    public let endsAt: String
    public let expiryPolicy: String
    public let state: String
    public let role: String
    public let memberCount: Int
    public let code: String?
    public let createdAt: String?
}

public struct ListGroupsResponse: Decodable, Equatable {
    public let groups: [GroupSummary]
}

/// A roster entry (§12.3) — always fully populated when present, unlike [GroupSummary].
public struct GroupMember: Decodable, Equatable {
    public let userId: String
    public let displayName: String
    public let role: String
    public let joinedAt: String
}

/// §12.3 — the §12.2 item plus the roster. `members` is `nil` for non-owner members during
/// `grace` (`state: "ended"`) — roster hidden per 005 §2.3; the owner and `archived` groups always
/// get the full roster.
public struct GroupDetail: Decodable, Equatable {
    public let groupId: String
    public let name: String
    public let endsAt: String
    public let expiryPolicy: String
    public let state: String
    public let role: String
    public let memberCount: Int
    public let code: String?
    public let createdAt: String
    public let members: [GroupMember]?
}

/// §12.4 request — at least one field (server-enforced; not duplicated client-side, matching
/// [UpdateMemberRequest]/[UpdateDeviceRequest], neither of which validate this either).
public struct UpdateGroupRequest: Encodable, Equatable {
    public let name: String?
    public let endsAt: String?
    public init(name: String? = nil, endsAt: String? = nil) {
        self.name = name
        self.endsAt = endsAt
    }
}

/// §12.6 request. `displayName` becomes the caller's **per-group** display name (005 §1) — same
/// REQUIRED-if-no-profile/optional-otherwise rule as [CreateGroupRequest.displayName].
public struct JoinGroupRequest: Encodable, Equatable {
    public let code: String
    public let displayName: String?
    public init(code: String, displayName: String? = nil) {
        self.code = code
        self.displayName = displayName
    }
}

/// §12.7 response.
public struct RotateGroupCodeResponse: Decodable, Equatable {
    public let code: String
    public let rotatedAt: String
}

/// §12.10 — **position-only** (005 §3): no `deviceId`/`deviceName`/`batteryPct`/`source`/altitude/
/// speed/bearing anywhere in this neighborhood, unlike §5.2's latest-location shapes.
public struct GroupPosition: Decodable, Equatable {
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double
    public let recordedAt: String
    public let receivedAt: String
    public let isStale: Bool
}

/// §12.10 — one entry per group member; `location` is `nil` when the member has no position yet
/// (roster parity with §5.2 — every member appears, present or not).
public struct GroupMemberLocation: Decodable, Equatable {
    public let userId: String
    public let displayName: String
    public let role: String
    public let location: GroupPosition?
}

public struct GroupLatestLocationsResponse: Decodable, Equatable {
    public let members: [GroupMemberLocation]
}

extension URLSessionAPIClient {
    /// Bootstraps a profile if the caller has none (§1.5.3) — `displayName` is REQUIRED then,
    /// optional otherwise (defaults server-side to the profile's).
    public func createGroup(name: String, endsAt: String, expiryPolicy: String, displayName: String?) async throws -> Envelope<GroupSummary> {
        try await send(method: .post, path: "groups", body: CreateGroupRequest(name: name, endsAt: endsAt, expiryPolicy: expiryPolicy, displayName: displayName))
    }

    /// Expired groups are filtered out server-side; `ended`/`archived` ones appear with their
    /// state (§12.2).
    public func listGroups() async throws -> Envelope<ListGroupsResponse> {
        try await send(method: .get, path: "groups")
    }

    /// §12.3 — the caller must be a group member; non-membership is masked as `GROUP_NOT_FOUND`
    /// (§12), same as a nonexistent `groupId`.
    public func getGroup(groupId: String) async throws -> Envelope<GroupDetail> {
        try await send(method: .get, path: "groups/\(groupId)")
    }

    /// Owner-only; at least one of `name`/`endsAt` must be non-`nil` (§12.4, server-enforced).
    public func updateGroup(groupId: String, name: String?, endsAt: String?) async throws -> Envelope<GroupSummary> {
        try await send(method: .patch, path: "groups/\(groupId)", body: UpdateGroupRequest(name: name, endsAt: endsAt))
    }

    /// Bare 204 (§12.5). Owner-only; immediate hard delete regardless of state/policy.
    public func deleteGroup(groupId: String) async throws {
        try await sendNoContent(method: .delete, path: "groups/\(groupId)")
    }

    /// Bootstraps a profile if the caller has none (§1.5.3) — `displayName` is REQUIRED then,
    /// optional otherwise; becomes the caller's per-group display name (005 §1).
    public func joinGroup(code: String, displayName: String?) async throws -> Envelope<GroupSummary> {
        try await send(method: .post, path: "groups/join", body: JoinGroupRequest(code: code, displayName: displayName))
    }

    /// Owner-only. The old code stops working instantly (§12.7).
    public func rotateGroupCode(groupId: String) async throws -> Envelope<RotateGroupCodeResponse> {
        try await send(method: .post, path: "groups/\(groupId)/code/rotate")
    }

    /// Bare 204 (§12.8). The owner cannot leave (`400 VALIDATION_FAILED`, `details.reason:
    /// "ownerCannotLeave"`) — they end (§12.4) or delete (§12.5) instead.
    public func leaveGroup(groupId: String) async throws {
        try await sendNoContent(method: .post, path: "groups/\(groupId)/leave")
    }

    /// Bare 204 (§12.9). Owner-only. Unknown/non-member `userId` → `404 MEMBER_NOT_FOUND`; the
    /// owner cannot kick themselves → `400 VALIDATION_FAILED`, `details.reason: "ownerCannotLeave"`.
    public func removeGroupMember(groupId: String, userId: String) async throws {
        try await sendNoContent(method: .delete, path: "groups/\(groupId)/members/\(userId)")
    }

    /// §12.10 — position-only (005 §3); only on `active` groups, else `410 GROUP_EXPIRED`.
    public func getGroupLatestLocations(groupId: String) async throws -> Envelope<GroupLatestLocationsResponse> {
        try await send(method: .get, path: "groups/\(groupId)/locations/latest")
    }
}
