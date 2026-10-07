import Foundation

// specs/001-api-contract.md §4 — device registration & listing wire shapes.

/// §4.1 request. Push tokens are OPTIONAL and omitted (never sent as an empty string) when not
/// yet available — an update that carries no token never clears a previously stored one
/// (server-side rule, 001 §4.1); the client simply doesn't send the key when it has nothing new.
public struct RegisterDeviceRequest: Encodable, Equatable {
    public let deviceId: String
    public let platform: String
    public let model: String
    public let appVersion: String
    public let pushToken: String?
    public let locationPushToken: String?
    public let deviceName: String?

    public init(
        deviceId: String,
        platform: String,
        model: String,
        appVersion: String,
        pushToken: String? = nil,
        locationPushToken: String? = nil,
        deviceName: String? = nil
    ) {
        self.deviceId = deviceId
        self.platform = platform
        self.model = model
        self.appVersion = appVersion
        self.pushToken = pushToken
        self.locationPushToken = locationPushToken
        self.deviceName = deviceName
    }
}

/// §4.1/§4.3 response shape. Push tokens are write-only (specs/001 §4.1) — by construction this
/// type simply has no token fields, never by filtering at decode time.
public struct DeviceResponse: Decodable, Equatable {
    public let deviceId: String
    public let ownerUserId: String
    public let platform: String
    public let deviceName: String
    public let model: String
    public let appVersion: String
    public let syncIntervalMinutes: Int
    public let trackingEnabled: Bool
    public let pushInvalid: Bool
    /// 001 §4.1 (011 §4.4) — the owner's opt-out of the STALE_NUDGE push. Absent -> `true`.
    public var staleNudgeEnabled: Bool = true
}

extension DeviceResponse {
    private enum CodingKeys: String, CodingKey {
        case deviceId, ownerUserId, platform, deviceName, model, appVersion
        case syncIntervalMinutes, trackingEnabled, pushInvalid, staleNudgeEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            deviceId: try c.decode(String.self, forKey: .deviceId),
            ownerUserId: try c.decode(String.self, forKey: .ownerUserId),
            platform: try c.decode(String.self, forKey: .platform),
            deviceName: try c.decode(String.self, forKey: .deviceName),
            model: try c.decode(String.self, forKey: .model),
            appVersion: try c.decode(String.self, forKey: .appVersion),
            syncIntervalMinutes: try c.decode(Int.self, forKey: .syncIntervalMinutes),
            trackingEnabled: try c.decode(Bool.self, forKey: .trackingEnabled),
            pushInvalid: try c.decode(Bool.self, forKey: .pushInvalid),
            staleNudgeEnabled: try c.decodeIfPresent(Bool.self, forKey: .staleNudgeEnabled) ?? true
        )
    }
}

/// §4.2 listing entry — the §4.1 response object plus `ownerDisplayName`/`lastSeenAt`/`isDormant`
/// (011 §2). Defensive defaults (003 §6): `lastSeenAt` absent -> `nil` (the card omits its "Last
/// seen" line), `isDormant` absent -> `false`, `staleNudgeEnabled` absent -> `true`.
public struct DeviceListItem: Decodable, Equatable {
    public let deviceId: String
    public let ownerUserId: String
    public let platform: String
    public let deviceName: String
    public let model: String
    public let appVersion: String
    public let syncIntervalMinutes: Int
    public let trackingEnabled: Bool
    public let pushInvalid: Bool
    public let ownerDisplayName: String
    public let lastSeenAt: String?
    public var isDormant: Bool = false
    public var staleNudgeEnabled: Bool = true
}

extension DeviceListItem {
    private enum CodingKeys: String, CodingKey {
        case deviceId, ownerUserId, platform, deviceName, model, appVersion
        case syncIntervalMinutes, trackingEnabled, pushInvalid, ownerDisplayName
        case lastSeenAt, isDormant, staleNudgeEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            deviceId: try c.decode(String.self, forKey: .deviceId),
            ownerUserId: try c.decode(String.self, forKey: .ownerUserId),
            platform: try c.decode(String.self, forKey: .platform),
            deviceName: try c.decode(String.self, forKey: .deviceName),
            model: try c.decode(String.self, forKey: .model),
            appVersion: try c.decode(String.self, forKey: .appVersion),
            syncIntervalMinutes: try c.decode(Int.self, forKey: .syncIntervalMinutes),
            trackingEnabled: try c.decode(Bool.self, forKey: .trackingEnabled),
            pushInvalid: try c.decode(Bool.self, forKey: .pushInvalid),
            ownerDisplayName: try c.decode(String.self, forKey: .ownerDisplayName),
            lastSeenAt: try c.decodeIfPresent(String.self, forKey: .lastSeenAt),
            isDormant: try c.decodeIfPresent(Bool.self, forKey: .isDormant) ?? false,
            staleNudgeEnabled: try c.decodeIfPresent(Bool.self, forKey: .staleNudgeEnabled) ?? true
        )
    }
}

public struct ListDevicesResponse: Decodable, Equatable {
    public let devices: [DeviceListItem]
}

/// §4.3 — at least one field; owner (non-parent) callers may set only `pushToken` (server-enforced,
/// `403 AUTH_FORBIDDEN` otherwise) — this type doesn't restrict at compile time, the caller's role
/// determines which fields are meaningful to send.
public struct UpdateDeviceRequest: Encodable, Equatable {
    public let syncIntervalMinutes: Int?
    public let trackingEnabled: Bool?
    public let deviceName: String?
    public let pushToken: String?
    /// 001 §4.3 (011 §4.4) — owner-only in every role; the client sends it alone.
    public let staleNudgeEnabled: Bool?

    public init(
        syncIntervalMinutes: Int? = nil,
        trackingEnabled: Bool? = nil,
        deviceName: String? = nil,
        pushToken: String? = nil,
        staleNudgeEnabled: Bool? = nil
    ) {
        self.staleNudgeEnabled = staleNudgeEnabled
        self.syncIntervalMinutes = syncIntervalMinutes
        self.trackingEnabled = trackingEnabled
        self.deviceName = deviceName
        self.pushToken = pushToken
    }
}

extension URLSessionAPIClient {
    public func registerDevice(_ request: RegisterDeviceRequest) async throws -> Envelope<DeviceResponse> {
        try await send(method: .post, path: "devices", body: request)
    }

    public func listDevices() async throws -> Envelope<ListDevicesResponse> {
        try await send(method: .get, path: "devices")
    }

    public func updateDevice(deviceId: String, _ request: UpdateDeviceRequest) async throws -> Envelope<DeviceResponse> {
        try await send(method: .patch, path: "devices/\(deviceId)", body: request)
    }

    /// 001 §4.4 (011 §1) — bare `204`, no envelope (the §3.6 convention).
    public func deleteDevice(deviceId: String) async throws {
        try await sendNoContent(method: .delete, path: "devices/\(deviceId)")
    }
}
