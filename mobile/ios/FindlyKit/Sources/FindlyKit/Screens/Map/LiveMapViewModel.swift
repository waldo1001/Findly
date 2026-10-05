import CoreGraphics
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
        /// specs/010-app-shell-and-screen-ux.md §2.1 — a confirmed `PROFILE_NOT_FOUND`/
        /// `FAMILY_NOT_FOUND` on this load. `GET /locations/latest` is family-scoped (001 §5.2,
        /// §1.5.4), so both variants are reachable. The screen MUST NOT render a retryable error
        /// card for this — it routes to Onboarding instead (there is nothing behind it worth
        /// going back to).
        case routeToOnboarding(OnboardingVariant)
    }

    @Published public private(set) var state: State = .loading
    /// Two-way bound to the map layer (`MapRendering`) so panning/zooming round-trips. Written ONLY
    /// when `cameraCommand` changes (see the `onChange` in `LiveMapScreen`) — never rewritten on an
    /// ordinary refresh, per specs/010-app-shell-and-screen-ux.md §3.4's "never yank the camera"
    /// rule.
    @Published public var region: MapRegion = .findlyDefault
    /// specs/010 §3.4 — a "consume-once" signal: present only on the exact call that decided to
    /// move the camera (first load, an explicit fit-all, or a selection that resolved a location).
    /// `LiveMapScreen` keys its camera-applying side effect on `cameraCommand?.sequence` alone, so
    /// an ordinary refresh that doesn't mint a new command never re-triggers it.
    @Published public private(set) var cameraCommand: MapCameraCommand?
    /// specs/010 §3.5 — the currently-highlighted roster member/marker, or `nil` when nothing is
    /// selected.
    @Published public private(set) var selectedUserId: String?
    /// specs/010 §3.4 (amended 2026-08-26, row I39) — the live map view's rendered size in points,
    /// threaded in from the render boundary (`LiveMapScreen`'s `GeometryReader`) so
    /// `MapRegion(fitting:viewSizePt:)` can convert the fixed 64pt bounds padding into an angular
    /// span — mirrors Android resolving `LocalDensity` at `GoogleMapRenderer`, never in the pure
    /// `MapCameraPolicy` decision. `LiveMapScreen` keeps this current; defaults to a common device
    /// size so a `.bounds` command that fires before the first real layout pass still produces a
    /// sane, non-degenerate region.
    public var mapViewportSizePt: CGSize = MapRegion.unmeasuredViewportSizePt
    /// specs/010-app-shell-and-screen-ux.md §3.4 "Occlusion model" (added 2026-09-07, row I49) —
    /// the roster sheet's height in points, kept current by `LiveMapScreen` from whatever detent
    /// is selected. Read only inside `emitCameraCommand`, at the moment a camera command is
    /// actually minted — matching "fit-all uses whatever detent is current at the moment it is
    /// invoked" and "a detent change MUST NOT move the camera" (a later change to this property
    /// alone never re-fits anything; only the next `load()`/`fitAll()`/`selectMember()` call does).
    public var sheetHeightPt: CGFloat = 0

    private let apiClient: FindlyAPIClient
    private var cameraPolicyState = MapCameraPolicyState.initial
    private var cameraSequence = 0
    private let refreshInterval: Duration
    private let refreshSleep: (Duration) async -> Void

    /// specs/010 §3.6 (rows A55/I59) — owns WHEN this screen refreshes (first appearance, every
    /// return to the foreground / to the map, every 30 s while visible and foregrounded, never in
    /// the background; at most one fetch in flight) and runs each refresh through `performRefresh`.
    /// `LiveMapScreen` forwards its SwiftUI lifecycle signals to it and does nothing else; the
    /// driver holds this view model weakly, so a discarded screen is not kept alive by its own timer.
    public private(set) lazy var refreshDriver = MapRefreshDriver(
        interval: refreshInterval,
        sleep: refreshSleep,
        perform: { [weak self] trigger in await self?.performRefresh(trigger) }
    )

    public init(
        apiClient: FindlyAPIClient,
        refreshInterval: Duration = MapRefreshDriver.defaultInterval,
        refreshSleep: @escaping (Duration) async -> Void = MapRefreshDriver.liveSleep
    ) {
        self.apiClient = apiClient
        self.refreshInterval = refreshInterval
        self.refreshSleep = refreshSleep
    }

    /// An EXPLICIT load: the §3.1 Refresh control and an error state's Retry (and every test that
    /// wants "load the roster now"). Goes through `refreshDriver` so the §3.6 one-request-in-flight
    /// rule covers it too — it returns immediately, doing nothing, if a fetch is already running.
    ///
    /// Shows `.loading` while it runs and reports its own failure as `.error`, exactly as before
    /// §3.6; the periodic/foreground refreshes `refreshDriver` schedules do neither (see
    /// `performRefresh`). Either way the pure `MapCameraPolicyState` machine (which persists on this
    /// instance across calls) is what withholds camera movement on a refresh, so "refresh never
    /// yanks the camera" holds regardless of which trigger ran.
    public func load() async {
        await refreshDriver.refresh()
    }

    /// One fetch of the roster for `trigger` — the `perform` closure of `refreshDriver`.
    ///
    /// specs/010 §3.6: only an `.explicit` refresh flips the sheet to `.loading` (the first
    /// appearance is already in it); a periodic/foreground/return refresh runs invisibly over the
    /// current content, so the map and roster never flash a spinner every 30 s. On failure
    /// `MapRefreshPolicy.failureOutcome` decides: with data on screen a background refresh keeps it
    /// silently; with none (a first load) or for an explicit Refresh the error state shows.
    ///
    /// The two routed 404s (010 §2.1) are NOT transient failures, so they route to Onboarding for
    /// every trigger — a poll that discovers the profile or family is gone must not keep showing the
    /// old family's positions — and end the refresh schedule.
    private func performRefresh(_ trigger: MapRefreshPolicy.Trigger) async {
        let hasDataOnScreen: Bool
        if case .loaded = state { hasDataOnScreen = true } else { hasDataOnScreen = false }
        if trigger == .explicit { state = .loading }
        do {
            let envelope = try await apiClient.getLatestLocations()
            apply(envelope.data.members)
        } catch {
            if let variant = onboardingRoutingOutcome(for: error) {
                state = .routeToOnboarding(variant)
                refreshDriver.end()
                return
            }
            switch MapRefreshPolicy.failureOutcome(for: trigger, hasDataOnScreen: hasDataOnScreen) {
            case .keepLastData: break
            case .showError: state = .error(userFacingMessage(for: error))
            }
        }
    }

    private func apply(_ members: [MemberLocations]) {
        // `@Published` republishes on every assignment, equal value or not; an unchanged 30 s poll
        // must not re-render the roster sheet.
        if state != .loaded(members) {
            state = .loaded(members)
        }

        // specs/010 §3.5 — a selection whose member disappeared from the roster (removed from
        // the family) no longer has anything to highlight.
        if let selectedUserId, !members.contains(where: { $0.userId == selectedUserId }) {
            self.selectedUserId = nil
        }

        let points = Self.locatedPoints(in: members)
        let hasPoints = !points.isEmpty
        // specs/010 §3.4 (normative) — decide WHETHER this load/refresh re-runs the camera
        // policy: only on the first successful load, or the first refresh that brings the
        // first-ever point in from a zero-point open. Never on an ordinary refresh after that,
        // even one whose marker set changed — this is the actual fix for "every marker-set
        // change yanks the camera".
        if MapCameraPolicy.shouldRunOnLoadOrRefresh(state: cameraPolicyState, hasPoints: hasPoints) {
            emitCameraCommand(MapCameraPolicy.target(points: points))
        }
        cameraPolicyState = MapCameraPolicy.nextState(state: cameraPolicyState, hasPoints: hasPoints)
    }

    /// specs/010 §3.5 (MUST): tapping a member's roster row/marker selects that member and animates
    /// the camera to their freshest located device at `MapCameraPolicy.singlePointZoom`. A member
    /// with no located device can still be selected (row/marker highlight) but the camera MUST NOT
    /// move. Tapping the already-selected member deselects (camera doesn't move either way).
    public func selectMember(_ userId: String) {
        guard case .loaded(let members) = state else { return }
        if selectedUserId == userId {
            selectedUserId = nil
            return
        }
        guard let member = members.first(where: { $0.userId == userId }) else { return }
        selectedUserId = userId
        if let freshest = MapCameraPolicy.freshestLocatedDevice(devices: member.devices),
           let lat = freshest.lat, let lon = freshest.lon {
            emitCameraCommand(.center(lat: lat, lon: lon, zoom: MapCameraPolicy.singlePointZoom))
        }
    }

    /// specs/010 §3.4's explicit fit-all action: re-runs `MapCameraPolicy.target` over the
    /// currently loaded points, unconditionally (the one trigger that always runs regardless of
    /// policy state).
    public func fitAll() {
        guard case .loaded(let members) = state else { return }
        emitCameraCommand(MapCameraPolicy.target(points: Self.locatedPoints(in: members)))
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
                    initials: Self.initials(for: member.displayName), isStale: device.isStale ?? true,
                    isSelected: member.userId == selectedUserId
                )
            }
        }
    }

    private static func locatedPoints(in members: [MemberLocations]) -> [MapGeoPoint] {
        members.flatMap { member in
            member.devices.compactMap { device -> MapGeoPoint? in
                guard let lat = device.lat, let lon = device.lon else { return nil }
                return MapGeoPoint(lat: lat, lon: lon)
            }
        }
    }

    private func emitCameraCommand(_ target: MapCameraTarget) {
        cameraSequence += 1
        cameraCommand = MapCameraCommand(sequence: cameraSequence, target: target)
        region = MapRegion(fitting: target, viewSizePt: mapViewportSizePt, sheetHeightPt: sheetHeightPt)
    }

    private static func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }
}
