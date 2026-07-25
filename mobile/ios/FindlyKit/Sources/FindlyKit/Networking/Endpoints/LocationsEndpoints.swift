import Foundation

// specs/001-api-contract.md §5 — location reporting & reading wire shapes.

public enum FixSource: String, Codable, Equatable {
    case periodic
    case locate
    case geofence
    case manual
}

/// §5.1 fix shape — also used verbatim by §6.3 fulfill and, as the offline queue's element type,
/// by `Locations/FixQueue.swift` (specs/004 §6).
public struct LocationFix: Codable, Equatable {
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

    public init(
        fixId: String,
        recordedAt: String,
        lat: Double,
        lon: Double,
        accuracyM: Double,
        altitudeM: Double? = nil,
        speedMps: Double? = nil,
        bearingDeg: Double? = nil,
        batteryPct: Int,
        source: FixSource
    ) {
        self.fixId = fixId
        self.recordedAt = recordedAt
        self.lat = lat
        self.lon = lon
        self.accuracyM = accuracyM
        self.altitudeM = altitudeM
        self.speedMps = speedMps
        self.bearingDeg = bearingDeg
        self.batteryPct = batteryPct
        self.source = source
    }
}

public struct ReportLocationsRequest: Encodable, Equatable {
    public let batchId: String
    public let fixes: [LocationFix]
    public init(batchId: String, fixes: [LocationFix]) {
        self.batchId = batchId
        self.fixes = fixes
    }
}

public struct DeviceSettingsSnapshot: Codable, Equatable {
    public let syncIntervalMinutes: Int
    public let trackingEnabled: Bool
}

public struct ReportLocationsResponse: Decodable, Equatable {
    public let accepted: Int
    public let duplicates: Int
    public let lastKnownUpdated: Bool
    public let deviceSettings: DeviceSettingsSnapshot
    public let geofenceEtag: String
}

public struct DeviceLocation: Decodable, Equatable {
    public let deviceId: String
    public let deviceName: String
    public let lat: Double?
    public let lon: Double?
    public let accuracyM: Double?
    public let recordedAt: String?
    public let receivedAt: String?
    public let batteryPct: Int?
    public let source: FixSource?
    public let trackingEnabled: Bool
    public let syncIntervalMinutes: Int
    public let isStale: Bool?
}

public struct MemberLocations: Decodable, Equatable {
    public let userId: String
    public let displayName: String
    public let devices: [DeviceLocation]
}

public struct LatestLocationsResponse: Decodable, Equatable {
    public let members: [MemberLocations]
}

public struct HistoryPoint: Decodable, Equatable {
    public let deviceId: String
    public let recordedAt: String
    public let lat: Double
    public let lon: Double
    public let accuracyM: Double
    public let batteryPct: Int
    public let source: FixSource
}

public struct LocationHistoryResponse: Decodable, Equatable {
    public let points: [HistoryPoint]
    public let nextCursor: String?
}

extension URLSessionAPIClient {
    /// specs/001 §1.2 — `X-Device-Id` REQUIRED (device-originated call).
    public func reportLocations(deviceId: String, batchId: String, fixes: [LocationFix]) async throws -> Envelope<ReportLocationsResponse> {
        try await send(method: .post, path: "locations", deviceId: deviceId, body: ReportLocationsRequest(batchId: batchId, fixes: fixes))
    }

    public func getLatestLocations() async throws -> Envelope<LatestLocationsResponse> {
        try await send(method: .get, path: "locations/latest")
    }

    public func getLocationHistory(
        userId: String, deviceId: String?, from: String, to: String, limit: Int?, cursor: String?
    ) async throws -> Envelope<LocationHistoryResponse> {
        var items = [URLQueryItem(name: "userId", value: userId), URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        if let deviceId { items.append(URLQueryItem(name: "deviceId", value: deviceId)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(method: .get, path: "locations/history", queryItems: items)
    }
}
