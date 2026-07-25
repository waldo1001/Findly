import Foundation

// specs/001-api-contract.md §7 — geofences wire shapes.

public struct Geofence: Codable, Equatable {
    public let geofenceId: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let radiusM: Double
    public let icon: String
    public let notifyOnEnter: Bool
    public let notifyOnExit: Bool

    public init(
        geofenceId: String, name: String, lat: Double, lon: Double, radiusM: Double,
        icon: String, notifyOnEnter: Bool, notifyOnExit: Bool
    ) {
        self.geofenceId = geofenceId
        self.name = name
        self.lat = lat
        self.lon = lon
        self.radiusM = radiusM
        self.icon = icon
        self.notifyOnEnter = notifyOnEnter
        self.notifyOnExit = notifyOnExit
    }
}

public struct GeofenceConfig: Decodable, Equatable {
    public let version: Int
    public let geofences: [Geofence]
}

/// §7.1 result — a `304` carries no body; modeled as a distinct case rather than an optional so
/// callers can't mistake "not modified" for "empty config".
public enum GeofencesResult: Equatable {
    case notModified
    case ok(GeofenceConfig, etag: String)
}

public struct ReplaceGeofencesRequest: Encodable, Equatable {
    public let geofences: [Geofence]
    public init(geofences: [Geofence]) {
        self.geofences = geofences
    }
}

public enum GeofenceTransition: String, Codable, Equatable {
    case enter
    case exit
}

public struct GeofenceEventReport: Encodable, Equatable {
    public let eventId: String
    public let geofenceId: String
    public let transition: GeofenceTransition
    public let recordedAt: String
    public init(eventId: String, geofenceId: String, transition: GeofenceTransition, recordedAt: String) {
        self.eventId = eventId
        self.geofenceId = geofenceId
        self.transition = transition
        self.recordedAt = recordedAt
    }
}

public struct ReportGeofenceEventsRequest: Encodable, Equatable {
    public let events: [GeofenceEventReport]
    public init(events: [GeofenceEventReport]) {
        self.events = events
    }
}

public struct ReportGeofenceEventsResponse: Decodable, Equatable {
    public let accepted: Int
    public let duplicates: Int
    public let deviceSettings: DeviceSettingsSnapshot
    public let geofenceEtag: String
}

public struct GeofenceEventHistoryItem: Decodable, Equatable {
    public let userId: String
    public let deviceId: String
    public let geofenceId: String
    public let geofenceName: String?
    public let lat: Double?
    public let lon: Double?
    public let radiusM: Double?
    public let transition: GeofenceTransition
    public let recordedAt: String
    public let receivedAt: String
}

public struct GeofenceEventHistoryResponse: Decodable, Equatable {
    public let events: [GeofenceEventHistoryItem]
    public let nextCursor: String?
}

extension URLSessionAPIClient {
    public func getGeofences(ifNoneMatch: String?) async throws -> GeofencesResult {
        var headers: [String: String] = [:]
        if let ifNoneMatch { headers["If-None-Match"] = ifNoneMatch }
        let (value, response): (Envelope<GeofenceConfig>?, HTTPURLResponse) = try await sendWithResponse(
            method: .get, path: "geofences", extraHeaders: headers, notModifiedIsSuccess: true
        )
        guard let value else { return .notModified }
        let etag = response.value(forHTTPHeaderField: "ETag") ?? ""
        return .ok(value.data, etag: etag)
    }

    public func replaceGeofences(_ geofences: [Geofence], ifMatch: String) async throws -> (config: Envelope<GeofenceConfig>, etag: String) {
        let (value, response): (Envelope<GeofenceConfig>?, HTTPURLResponse) = try await sendWithResponse(
            method: .put, path: "geofences", body: ReplaceGeofencesRequest(geofences: geofences), extraHeaders: ["If-Match": ifMatch]
        )
        let etag = response.value(forHTTPHeaderField: "ETag") ?? ""
        return (value!, etag)
    }

    /// specs/001 §1.2 — `X-Device-Id` REQUIRED (device-originated call).
    public func reportGeofenceEvents(deviceId: String, events: [GeofenceEventReport]) async throws -> Envelope<ReportGeofenceEventsResponse> {
        try await send(method: .post, path: "geofence-events", deviceId: deviceId, body: ReportGeofenceEventsRequest(events: events))
    }

    public func getGeofenceEventHistory(
        from: String, to: String, userId: String?, limit: Int?, cursor: String?
    ) async throws -> Envelope<GeofenceEventHistoryResponse> {
        var items = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        if let userId { items.append(URLQueryItem(name: "userId", value: userId)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(method: .get, path: "geofence-events", queryItems: items)
    }
}
