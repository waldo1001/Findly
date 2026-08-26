import Foundation

/// specs/010-app-shell-and-screen-ux.md §3.4 (normative, promoted from Android's `MapCamera.kt`) —
/// the platform/SDK-agnostic camera DECISION: pure, unit-testable logic with no MapKit dependency,
/// exactly mirroring `MapCamera.target` (mobile/android/app/src/main/java/com/findly/android/ui/
/// map/MapCamera.kt). This retires `LiveMapViewModel`'s previous "center on the first annotation
/// with a fixed 0.05° span" behavior, which opened a two-country family on one member.
///
/// A geographic point, `Equatable`/`Hashable` so a list of points can be de-duplicated (mirrors
/// Kotlin's `List<Pair<Double, Double>>.distinct()`, which plain Swift tuples cannot do — tuples
/// are not `Hashable`).
public struct MapGeoPoint: Equatable, Hashable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Deliberately independent of `MapKit`/`CoreLocation` types, same rationale as `MapCamera.kt`'s
/// header doc: keeps this logic testable on any host, including this session's Command-Line-Tools-
/// only macOS, with no map framework at all.
public enum MapCameraTarget: Equatable {
    /// No marker has a known position yet — a calm, zoomed-out default rather than the (0, 0)
    /// "null island" a naive empty-bounds calculation would produce.
    case defaultRegion(lat: Double, lon: Double, zoom: Double)
    /// Exactly one distinct marker position (including "every marker is at the same spot") —
    /// centering beats fitting a zero-area bounds.
    case center(lat: Double, lon: Double, zoom: Double)
    /// Two or more distinct marker positions — fit them all with padding. Only the geographic
    /// corners are decided here; `MapRegion(fitting:)` does the platform-specific translation.
    /// `paddingPt` is already device-independent on iOS (unlike Android's raw pixels, which needed
    /// a separate density conversion at the renderer) — see specs/010 §3.4's "64 dp/pt" wording.
    case bounds(southLat: Double, northLat: Double, westLon: Double, eastLon: Double, paddingPt: Double)
}

/// A "consume-once" wrapper around a decided `MapCameraTarget` (specs/010 §3.4). `sequence` is a
/// monotonically increasing number minted by whichever view model decided a run should happen
/// (`LiveMapViewModel`/`GroupMapViewModel`). The screen layer keys its camera-applying side effect
/// on `sequence` alone (not on the annotation list) — a refresh that changes markers but does
/// **not** mint a new command therefore produces no new `sequence`, and the effect simply does not
/// re-run. That is the actual fix for "every marker-set change yanks the camera" (010 §3.4).
public struct MapCameraCommand: Equatable {
    public let sequence: Int
    public let target: MapCameraTarget

    public init(sequence: Int, target: MapCameraTarget) {
        self.sequence = sequence
        self.target = target
    }
}

/// specs/010-app-shell-and-screen-ux.md §3.4 — decides WHEN the camera policy re-runs, as pure
/// state kept independent of `MapCameraPolicy.target` (which decides WHERE once a run happens).
/// MUST run: the first successful load, an explicit fit-all action, or a member selection. MUST
/// NOT run on an ordinary refresh — even one whose marker set changed — except the one carve-out
/// the spec grants: a screen that opened with zero located points still gets exactly one run the
/// first time any point arrives.
public struct MapCameraPolicyState: Equatable {
    public var hasRunInitial: Bool
    public var hadAnyPoint: Bool

    public init(hasRunInitial: Bool = false, hadAnyPoint: Bool = false) {
        self.hasRunInitial = hasRunInitial
        self.hadAnyPoint = hadAnyPoint
    }

    public static let initial = MapCameraPolicyState()
}

public enum MapCameraPolicy {
    /// Ghent, Belgium — matches Android's `MapCamera.DEFAULT_LAT`/`DEFAULT_LON` and the pre-existing
    /// `MapRegion.findlyDefault`, so both apps open on the same calm default before any family
    /// location has ever been reported.
    public static let defaultLat = 51.0543
    public static let defaultLon = 3.7174
    public static let defaultZoom = 4.0
    public static let singlePointZoom = 15.0
    public static let boundsPaddingPt = 64.0

    /// `points` are every device/member with a known position — callers MUST already have
    /// filtered out devices with no fix (001 §5.2/§12.10's "no location yet" devices carry no
    /// coordinate to plot).
    public static func target(points: [MapGeoPoint]) -> MapCameraTarget {
        let distinct = Array(Set(points))
        switch distinct.count {
        case 0:
            return .defaultRegion(lat: defaultLat, lon: defaultLon, zoom: defaultZoom)
        case 1:
            let point = distinct[0]
            return .center(lat: point.lat, lon: point.lon, zoom: singlePointZoom)
        default:
            let lats = distinct.map(\.lat)
            let lons = distinct.map(\.lon)
            return .bounds(
                southLat: lats.min()!, northLat: lats.max()!,
                westLon: lons.min()!, eastLon: lons.max()!,
                paddingPt: boundsPaddingPt
            )
        }
    }

    /// True on: the very first load/refresh ever (regardless of point count — a screen that opens
    /// with zero points still gets its one "settle on the calm default" run), or the first later
    /// refresh that brings the first-ever point in from a zero-point open. False on every refresh
    /// after that, even one whose marker set changed — the 010 §3.4 rule this exists to enforce.
    ///
    /// Deliberately returns `true` unconditionally right now — a wrong-on-purpose stub so the
    /// first test run is an assertion failure, not a compile error (per this task's TDD mandate).
    public static func shouldRunOnLoadOrRefresh(state: MapCameraPolicyState, hasPoints: Bool) -> Bool {
        true
    }

    public static func nextState(state: MapCameraPolicyState, hasPoints: Bool) -> MapCameraPolicyState {
        MapCameraPolicyState(hasRunInitial: true, hadAnyPoint: state.hadAnyPoint || hasPoints)
    }

    /// specs/010 §3.5 / §10 "Freshest-device resolution": newest `recordedAt` among located
    /// devices wins; devices without a fix are never chosen.
    ///
    /// Deliberately returns `nil` unconditionally right now — the wrong-on-purpose stub.
    public static func freshestLocatedDevice(devices: [DeviceLocation]) -> DeviceLocation? {
        nil
    }
}
