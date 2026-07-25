import Foundation

// specs/001-api-contract.md §6 — push-to-locate wire shapes.

/// §6.1 request — exactly one of `targetUserId` | `targetDeviceId` (custom `Encodable` emits only
/// the chosen key, matching the wire shape exactly rather than sending the other as `null`).
public enum LocateTarget: Equatable {
    case user(String)
    case device(String)
}

extension LocateTarget: Encodable {
    private enum CodingKeys: String, CodingKey {
        case targetUserId
        case targetDeviceId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let userId):
            try container.encode(userId, forKey: .targetUserId)
        case .device(let deviceId):
            try container.encode(deviceId, forKey: .targetDeviceId)
        }
    }
}

public enum LocateStatus: String, Codable, Equatable {
    case pending
    case fulfilled
    case expired
    case pushFailed
}

public struct LastKnownFix: Decodable, Equatable {
    public let deviceId: String
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double
    public let recordedAt: String
}

public struct CreateLocateRequestResponse: Decodable, Equatable {
    public let requestId: String
    public let status: LocateStatus
    public let targetUserId: String
    public let targetDeviceId: String
    public let expiresAt: String
    public let lastKnown: LastKnownFix?
}

/// §5.1 fix shape + `deviceId`, as returned by §6.2 poll once fulfilled.
public struct FulfilledFix: Decodable, Equatable {
    public let deviceId: String
    public let fixId: String
    public let recordedAt: String
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double
    public let altitudeM: Double?
    public let speedMps: Double?
    public let bearingDeg: Double?
    public let batteryPct: Int
    public let source: FixSource
}

public struct PollLocateRequestResponse: Decodable, Equatable {
    public let requestId: String
    public let status: LocateStatus
    public let expiresAt: String
    public let fix: FulfilledFix?
}

public struct FulfillLocateRequestBody: Encodable, Equatable {
    public let fix: LocationFix
    public init(fix: LocationFix) {
        self.fix = fix
    }
}

public struct FulfillLocateRequestResponse: Decodable, Equatable {
    public let status: String
}

extension URLSessionAPIClient {
    public func createLocateRequest(target: LocateTarget) async throws -> Envelope<CreateLocateRequestResponse> {
        try await send(method: .post, path: "locate-requests", body: target)
    }

    public func pollLocateRequest(requestId: String) async throws -> Envelope<PollLocateRequestResponse> {
        try await send(method: .get, path: "locate-requests/\(requestId)")
    }

    /// specs/001 §1.2 — `X-Device-Id` REQUIRED, MUST equal the request's target.
    public func fulfillLocateRequest(deviceId: String, requestId: String, fix: LocationFix) async throws -> Envelope<FulfillLocateRequestResponse> {
        try await send(method: .post, path: "locate-requests/\(requestId)/fulfill", deviceId: deviceId, body: FulfillLocateRequestBody(fix: fix))
    }
}
