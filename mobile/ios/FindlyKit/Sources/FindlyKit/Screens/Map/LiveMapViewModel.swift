import Foundation

/// specs/004-ios-client.md I2 (001 §5.2) — the family map/roster. One `GET /locations/latest` call
/// returns the whole family; members with no registered devices, and devices with no fix yet, are
/// both included per §5.2 and rendered by the roster (not just the map layer).
@MainActor
public final class LiveMapViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded([MemberLocations])
        case error(String)
    }

    @Published public private(set) var state: State = .loading
    /// Two-way bound to the map layer (`MapRendering`) so panning/zooming round-trips; recentered
    /// on the first annotation whenever a fresh `load()` succeeds.
    @Published public var region: MapRegion = .findlyDefault

    private let apiClient: FindlyAPIClient

    public init(apiClient: FindlyAPIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getLatestLocations()
            state = .loaded(envelope.data.members)
            if let first = annotations(for: envelope.data.members).first {
                region = MapRegion(centerLat: first.lat, centerLon: first.lon)
            }
        } catch {
            state = .error(userFacingMessage(for: error))
        }
    }

    /// Every device with a known position, across every member — `MapMarkerBubble`-ready. Devices
    /// with `lat`/`lon` both `nil` (never reported, §5.2) are excluded here; they still show up in
    /// the roster list via `state`.
    public var annotations: [MapAnnotationItem] {
        guard case let .loaded(members) = state else { return [] }
        return annotations(for: members)
    }

    private func annotations(for members: [MemberLocations]) -> [MapAnnotationItem] {
        members.flatMap { member in
            member.devices.compactMap { device -> MapAnnotationItem? in
                guard let lat = device.lat, let lon = device.lon else { return nil }
                return MapAnnotationItem(
                    id: device.deviceId, lat: lat, lon: lon,
                    initials: Self.initials(for: member.displayName), isStale: device.isStale ?? true
                )
            }
        }
    }

    private static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
