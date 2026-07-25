import Foundation

// specs/001-api-contract.md §3 — family management wire shapes.

public struct CreateFamilyRequest: Encodable, Equatable {
    public let familyName: String
    public let displayName: String
    public init(familyName: String, displayName: String) {
        self.familyName = familyName
        self.displayName = displayName
    }
}

/// §3.1 response `member` — no `joinedAt` (unlike the §3.2 roster shape).
public struct MemberSummary: Decodable, Equatable {
    public let userId: String
    public let role: String
    public let displayName: String
}

public struct CreateFamilyResponse: Decodable, Equatable {
    public let familyId: String
    public let familyName: String
    public let member: MemberSummary
}

/// §3.2 roster entry — includes `joinedAt`; also the §3.5 update-member response shape.
public struct FamilyMember: Decodable, Equatable {
    public let userId: String
    public let role: String
    public let displayName: String
    public let joinedAt: String
}

public struct MeSummary: Decodable, Equatable {
    public let userId: String
    public let role: String
}

public struct GetMyFamilyResponse: Decodable, Equatable {
    public let familyId: String
    public let familyName: String
    public let createdAt: String
    public let me: MeSummary
    public let members: [FamilyMember]
}

public struct CreateInviteRequest: Encodable, Equatable {
    public let role: String
    public let emailHint: String?
    public init(role: String, emailHint: String? = nil) {
        self.role = role
        self.emailHint = emailHint
    }
}

public struct CreateInviteResponse: Decodable, Equatable {
    public let inviteCode: String
    public let role: String
    public let expiresAt: String
}

public struct AcceptInviteRequest: Encodable, Equatable {
    public let inviteCode: String
    public let displayName: String
    public init(inviteCode: String, displayName: String) {
        self.inviteCode = inviteCode
        self.displayName = displayName
    }
}

public struct AcceptInviteResponse: Decodable, Equatable {
    public let familyId: String
    public let familyName: String
    public let role: String
}

/// §3.5 — at least one field; `nil` fields are omitted from the JSON body (Swift's derived
/// `Encodable` uses `encodeIfPresent` for `Optional` properties), never sent as `null`.
public struct UpdateMemberRequest: Encodable, Equatable {
    public let role: String?
    public let displayName: String?
    public init(role: String? = nil, displayName: String? = nil) {
        self.role = role
        self.displayName = displayName
    }
}

extension URLSessionAPIClient {
    public func createFamily(familyName: String, displayName: String) async throws -> Envelope<CreateFamilyResponse> {
        try await send(method: .post, path: "families", body: CreateFamilyRequest(familyName: familyName, displayName: displayName))
    }

    public func getMyFamily() async throws -> Envelope<GetMyFamilyResponse> {
        try await send(method: .get, path: "families/me")
    }

    public func createInvite(role: String, emailHint: String?) async throws -> Envelope<CreateInviteResponse> {
        try await send(method: .post, path: "families/me/invites", body: CreateInviteRequest(role: role, emailHint: emailHint))
    }

    public func acceptInvite(inviteCode: String, displayName: String) async throws -> Envelope<AcceptInviteResponse> {
        try await send(method: .post, path: "invites/accept", body: AcceptInviteRequest(inviteCode: inviteCode, displayName: displayName))
    }

    public func updateMember(userId: String, role: String?, displayName: String?) async throws -> Envelope<FamilyMember> {
        try await send(method: .patch, path: "families/me/members/\(userId)", body: UpdateMemberRequest(role: role, displayName: displayName))
    }

    public func removeMember(userId: String) async throws {
        try await sendNoContent(method: .delete, path: "families/me/members/\(userId)")
    }
}
