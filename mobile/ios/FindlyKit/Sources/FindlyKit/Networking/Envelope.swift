import Foundation

/// specs/001-api-contract.md §1.3 — every success response body.
public struct Envelope<T: Decodable>: Decodable {
    public let data: T
    public let features: Features
}

/// specs/001-api-contract.md §9 — present in every success envelope; derived server-side only
/// from `PLAN_MATRIX`. Clients never send entitlement data, only read this object.
public struct Features: Decodable, Equatable {
    public let subscriptionStatus: String
    public let limits: PlanLimits
    public let flags: PlanFlags
}

public struct PlanLimits: Decodable, Equatable {
    public let maxDevices: Int
    public let maxGeofences: Int
    public let historyDays: Int
    public let minSyncIntervalMinutes: Int
    public let locateRequestsPerDay: Int
    /// specs/005-temporary-groups.md additions to 001 §9 — `nil` on any envelope fixture
    /// predating groups. **Deliberately no inline `= nil`** on these `let`s: Swift's synthesized
    /// `Decodable` treats a stored property with an initial value as never-decoded (always the
    /// literal default, a real footgun — confirmed by the compiler's own "will not be decoded"
    /// warning when this was tried) — so decode-from-JSON relies solely on the type being
    /// `Optional` (`decodeIfPresent`), and the `= nil` default for *direct* Swift construction
    /// lives on the explicit initializer below instead.
    public let maxActiveGroups: Int?
    public let maxGroupMembers: Int?
    public let maxGroupDurationDays: Int?
    public let groupGraceDays: Int?

    public init(
        maxDevices: Int, maxGeofences: Int, historyDays: Int, minSyncIntervalMinutes: Int,
        locateRequestsPerDay: Int, maxActiveGroups: Int? = nil, maxGroupMembers: Int? = nil,
        maxGroupDurationDays: Int? = nil, groupGraceDays: Int? = nil
    ) {
        self.maxDevices = maxDevices
        self.maxGeofences = maxGeofences
        self.historyDays = historyDays
        self.minSyncIntervalMinutes = minSyncIntervalMinutes
        self.locateRequestsPerDay = locateRequestsPerDay
        self.maxActiveGroups = maxActiveGroups
        self.maxGroupMembers = maxGroupMembers
        self.maxGroupDurationDays = maxGroupDurationDays
        self.groupGraceDays = groupGraceDays
    }
}

public struct PlanFlags: Decodable, Equatable {
    public let pushToLocate: Bool
    public let geofencing: Bool
    public let historyReplay: Bool
    /// specs/005-temporary-groups.md addition to 001 §9 — defaults to `false` when the key is
    /// absent (any envelope fixture predating groups), via the custom decoder below (a plain
    /// `Bool` property, unlike [PlanLimits]'s new fields, doesn't get this for free from the
    /// synthesized decoder).
    public let groups: Bool

    public init(pushToLocate: Bool, geofencing: Bool, historyReplay: Bool, groups: Bool = false) {
        self.pushToLocate = pushToLocate
        self.geofencing = geofencing
        self.historyReplay = historyReplay
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey {
        case pushToLocate, geofencing, historyReplay, groups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pushToLocate = try container.decode(Bool.self, forKey: .pushToLocate)
        geofencing = try container.decode(Bool.self, forKey: .geofencing)
        historyReplay = try container.decode(Bool.self, forKey: .historyReplay)
        groups = try container.decodeIfPresent(Bool.self, forKey: .groups) ?? false
    }
}

/// specs/001-api-contract.md §1.3, §10 — every error response body.
public struct APIErrorBody: Decodable, Equatable {
    public let code: APIErrorCode
    public let message: String
    public let details: [String: JSONValue]?
    public let requestId: String
}

public struct APIErrorEnvelope: Decodable, Equatable {
    public let error: APIErrorBody
}

/// Thrown by `FindlyAPIClient` implementations when the server returns a non-2xx response that
/// decodes as `APIErrorEnvelope`, or when the response cannot be understood at all.
public enum APIError: Error, Equatable {
    case server(APIErrorBody, httpStatus: Int)
    case notModified
    case transport(String)
    case decoding(String)
}
