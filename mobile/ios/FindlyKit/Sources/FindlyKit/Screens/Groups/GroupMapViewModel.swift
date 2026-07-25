import Foundation

/// specs/004-ios-client.md §3.4 (001 §12.10; 005 §3) — the group's live, position-only map. One
/// `GET /groups/{id}/locations/latest` call; every member appears (roster parity with §5.2),
/// `location: nil` = no position yet. Deliberately no `deviceId`/`deviceName`/`batteryPct`/`source`/
/// altitude/speed/bearing anywhere near this type (005 §3) — the DTO simply doesn't carry them.
///
/// Only reachable on `active` groups (005 §2.3) — `410 GROUP_EXPIRED` is a distinct `.expired`
/// state (not `.error`), so the screen can bounce back to the groups list rather than offering a
/// retry that will never succeed.
@MainActor
public final class GroupMapViewModel: ObservableObject {
    public enum State: Equatable {
        case loading
        case loaded([GroupMemberLocation])
        case error(String)
        case expired
    }

    @Published public private(set) var state: State = .loading
    /// Two-way bound to the map layer (`MapRendering`), recentered on the first annotation
    /// whenever a fresh `load()` succeeds — same pattern as `LiveMapViewModel`.
    @Published public var region: MapRegion = .findlyDefault

    private let apiClient: FindlyAPIClient
    public let groupId: String

    public init(apiClient: FindlyAPIClient, groupId: String) {
        self.apiClient = apiClient
        self.groupId = groupId
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getGroupLatestLocations(groupId: groupId)
            state = .loaded(envelope.data.members)
            if let first = annotations(for: envelope.data.members).first {
                region = MapRegion(centerLat: first.lat, centerLon: first.lon)
            }
        } catch {
            if (error as? APIError)?.serverCode == .groupExpired {
                state = .expired
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    /// Every member with a known position — `MapMarkerBubble`-ready. Members with no position yet
    /// are excluded here; they still appear in the roster list via `state`.
    public var annotations: [MapAnnotationItem] {
        guard case let .loaded(members) = state else { return [] }
        return annotations(for: members)
    }

    private func annotations(for members: [GroupMemberLocation]) -> [MapAnnotationItem] {
        members.compactMap { member in
            guard let location = member.location else { return nil }
            return MapAnnotationItem(
                id: member.userId, lat: location.lat, lon: location.lon,
                initials: Self.initials(for: member.displayName), isStale: location.isStale
            )
        }
    }

    private static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
