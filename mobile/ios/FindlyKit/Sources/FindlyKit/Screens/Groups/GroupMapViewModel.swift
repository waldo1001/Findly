import CoreGraphics
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
    /// Two-way bound to the map layer (`MapRendering`). Written ONLY when `cameraCommand` changes
    /// (specs/010-app-shell-and-screen-ux.md §3.2/§3.4 — the group map adopts the same camera
    /// policy through the same renderer seam as `LiveMapViewModel`), never rewritten on an
    /// ordinary refresh.
    @Published public var region: MapRegion = .findlyDefault
    /// specs/010 §3.4 — mirrors `LiveMapViewModel.cameraCommand` exactly.
    @Published public private(set) var cameraCommand: MapCameraCommand?
    /// specs/010 §3.5 — mirrors `LiveMapViewModel.selectedUserId`; position-only, so selection
    /// targets the member's own single point directly rather than resolving a freshest device.
    @Published public private(set) var selectedUserId: String?
    /// specs/010 §3.4 (amended 2026-08-26, row I39) — mirrors `LiveMapViewModel.mapViewportSizePt`
    /// exactly: the live map view's rendered size in points, kept current by `GroupMapScreen`'s
    /// `GeometryReader`, so the fixed 64pt bounds padding converts to an angular span at the render
    /// boundary rather than in the pure `MapCameraPolicy` decision.
    public var mapViewportSizePt: CGSize = MapRegion.unmeasuredViewportSizePt

    private let apiClient: FindlyAPIClient
    public let groupId: String
    private var cameraPolicyState = MapCameraPolicyState.initial
    private var cameraSequence = 0

    public init(apiClient: FindlyAPIClient, groupId: String) {
        self.apiClient = apiClient
        self.groupId = groupId
    }

    public func load() async {
        state = .loading
        do {
            let envelope = try await apiClient.getGroupLatestLocations(groupId: groupId)
            let members = envelope.data.members
            state = .loaded(members)

            if let selectedUserId, !members.contains(where: { $0.userId == selectedUserId }) {
                self.selectedUserId = nil
            }

            let points = Self.locatedPoints(in: members)
            let hasPoints = !points.isEmpty
            if MapCameraPolicy.shouldRunOnLoadOrRefresh(state: cameraPolicyState, hasPoints: hasPoints) {
                emitCameraCommand(MapCameraPolicy.target(points: points))
            }
            cameraPolicyState = MapCameraPolicy.nextState(state: cameraPolicyState, hasPoints: hasPoints)
        } catch {
            if (error as? APIError)?.serverCode == .groupExpired {
                state = .expired
            } else {
                state = .error(userFacingMessage(for: error))
            }
        }
    }

    /// specs/010 §3.5, position-only mirror of `LiveMapViewModel.selectMember` — there is exactly
    /// one point per member here, so selection targets it directly rather than resolving a
    /// freshest device first.
    public func selectMember(_ userId: String) {
        guard case .loaded(let members) = state else { return }
        if selectedUserId == userId {
            selectedUserId = nil
            return
        }
        guard let member = members.first(where: { $0.userId == userId }) else { return }
        selectedUserId = userId
        if let location = member.location {
            emitCameraCommand(.center(lat: location.lat, lon: location.lon, zoom: MapCameraPolicy.singlePointZoom))
        }
    }

    /// specs/010 §3.4's explicit fit-all action — mirrors `LiveMapViewModel.fitAll`.
    public func fitAll() {
        guard case .loaded(let members) = state else { return }
        emitCameraCommand(MapCameraPolicy.target(points: Self.locatedPoints(in: members)))
    }

    private static func locatedPoints(in members: [GroupMemberLocation]) -> [MapGeoPoint] {
        members.compactMap { member in
            guard let location = member.location else { return nil }
            return MapGeoPoint(lat: location.lat, lon: location.lon)
        }
    }

    private func emitCameraCommand(_ target: MapCameraTarget) {
        cameraSequence += 1
        cameraCommand = MapCameraCommand(sequence: cameraSequence, target: target)
        region = MapRegion(fitting: target, viewSizePt: mapViewportSizePt)
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
                initials: Self.initials(for: member.displayName), isStale: location.isStale,
                isSelected: member.userId == selectedUserId
            )
        }
    }

    private static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
