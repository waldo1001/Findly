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
        /// specs/010 §2.1 / §3.6 — a confirmed `404 PROFILE_NOT_FOUND` on a (re)load. Group screens
        /// need a PROFILE, not a family, so `FAMILY_NOT_FOUND` is deliberately NOT routed here.
        case routeToOnboarding(OnboardingVariant)
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
    /// specs/010-app-shell-and-screen-ux.md §3.4 "Occlusion model" (added 2026-09-07, row I49) —
    /// mirrors `LiveMapViewModel.sheetHeightPt` exactly, kept current by `GroupMapScreen` from
    /// whatever detent is selected.
    public var sheetHeightPt: CGFloat = 0

    private let apiClient: FindlyAPIClient
    public let groupId: String
    private var cameraPolicyState = MapCameraPolicyState.initial
    private var cameraSequence = 0
    private let refreshInterval: Duration
    private let refreshSleep: (Duration) async -> Void

    /// specs/010 §3.2/§3.6 (rows A55/I59) — mirrors `LiveMapViewModel.refreshDriver` exactly: owns
    /// WHEN the group map refreshes and runs each refresh through `performRefresh`.
    public private(set) lazy var refreshDriver = MapRefreshDriver(
        interval: refreshInterval,
        sleep: refreshSleep,
        adopted: { [weak self] in self?.showRefreshing() },
        perform: { [weak self] trigger in await self?.performRefresh(trigger) }
    )

    public init(
        apiClient: FindlyAPIClient,
        groupId: String,
        refreshInterval: Duration = MapRefreshDriver.defaultInterval,
        refreshSleep: @escaping (Duration) async -> Void = MapRefreshDriver.liveSleep
    ) {
        self.apiClient = apiClient
        self.groupId = groupId
        self.refreshInterval = refreshInterval
        self.refreshSleep = refreshSleep
    }

    /// An EXPLICIT load (Refresh / Retry) — mirrors `LiveMapViewModel.load()`: goes through
    /// `refreshDriver` so the §3.6 one-request-in-flight rule covers it, shows `.loading` while it
    /// runs and reports its own failure; if an automatic fetch is already running it ADOPTS it (no
    /// second request, `showRefreshing()` now, the failure reported as its own).
    public func load() async {
        await refreshDriver.refresh()
    }

    /// One fetch of the group roster for `trigger` — mirrors `LiveMapViewModel.performRefresh`
    /// (specs/010 §3.2/§3.6).
    ///
    /// A CONFIRMED STATE CHANGE is not a failed refresh, whatever triggered the fetch (§3.6; 001
    /// §12.10): each surfaces exactly as on a first load and ENDS polling, because every later poll
    /// would get the same answer —
    /// - `410 GROUP_EXPIRED` → `.expired` (005 §2.3: the screen swaps to "This group has ended");
    /// - `404 GROUP_NOT_FOUND` (a removed member, a deleted or swept group) → the first-load error
    ///   outcome, `.error` (its Retry still works — a tap is not polling);
    /// - `404 PROFILE_NOT_FOUND` → route to Onboarding (010 §2.1). Group screens need a profile, not
    ///   a family, so `FAMILY_NOT_FOUND` is deliberately NOT here: it is an ordinary failure.
    private func performRefresh(_ trigger: MapRefreshPolicy.Trigger) async {
        let hasDataOnScreen: Bool
        if case .loaded = state { hasDataOnScreen = true } else { hasDataOnScreen = false }
        if trigger == .explicit { state = .loading }
        do {
            let envelope = try await apiClient.getGroupLatestLocations(groupId: groupId)
            apply(envelope.data.members)
        } catch {
            switch (error as? APIError)?.serverCode {
            case .groupExpired:
                state = .expired
                refreshDriver.end()
                return
            case .groupNotFound:
                state = .error(userFacingMessage(for: error))
                refreshDriver.end()
                return
            case .profileNotFound:
                state = .routeToOnboarding(.profileLess)
                refreshDriver.end()
                return
            default:
                break
            }
            // The trigger as it is NOW, not as the fetch started: an explicit Refresh that adopted
            // this fetch while it ran upgraded it, and its failure must then surface (§3.6).
            let effectiveTrigger = refreshDriver.inFlightTrigger ?? trigger
            switch MapRefreshPolicy.failureOutcome(for: effectiveTrigger, hasDataOnScreen: hasDataOnScreen) {
            case .keepLastData: break
            case .showError: state = .error(userFacingMessage(for: error))
            }
        }
    }

    /// §3.6 adoption — mirrors `LiveMapViewModel.showRefreshing()`.
    private func showRefreshing() {
        switch state {
        case .loaded, .error: state = .loading
        case .loading, .expired, .routeToOnboarding: break
        }
    }

    private func apply(_ members: [GroupMemberLocation]) {
        // An unchanged 30 s poll must not republish (and so re-render) the roster sheet.
        if state != .loaded(members) {
            state = .loaded(members)
        }

        if let selectedUserId, !members.contains(where: { $0.userId == selectedUserId }) {
            self.selectedUserId = nil
        }

        let points = Self.locatedPoints(in: members)
        let hasPoints = !points.isEmpty
        if MapCameraPolicy.shouldRunOnLoadOrRefresh(state: cameraPolicyState, hasPoints: hasPoints) {
            emitCameraCommand(MapCameraPolicy.target(points: points))
        }
        cameraPolicyState = MapCameraPolicy.nextState(state: cameraPolicyState, hasPoints: hasPoints)
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
        region = MapRegion(fitting: target, viewSizePt: mapViewportSizePt, sheetHeightPt: sheetHeightPt)
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
