import CoreGraphics
import Foundation

/// specs/004-ios-client.md I2 (001 §5.2) — a platform-agnostic map viewport, decoupled from
/// `MKCoordinateRegion` so a `MapRendering` implementation that doesn't use MapKit never needs to
/// import it — keeps the map-provider seam genuinely swappable.
public struct MapRegion: Equatable {
    public var centerLat: Double
    public var centerLon: Double
    public var spanLatDelta: Double
    public var spanLonDelta: Double

    public init(centerLat: Double, centerLon: Double, spanLatDelta: Double = 0.05, spanLonDelta: Double = 0.05) {
        self.centerLat = centerLat
        self.centerLon = centerLon
        self.spanLatDelta = spanLatDelta
        self.spanLonDelta = spanLonDelta
    }

    /// A reasonable default viewport before the first family fix arrives.
    public static let findlyDefault = MapRegion(centerLat: 51.0543, centerLon: 3.7174)

    /// specs/010-app-shell-and-screen-ux.md §3.4 (amended 2026-08-26, row I39) — a common device
    /// logical size, used ONLY as the pre-layout fallback for `LiveMapViewModel.mapViewportSizePt`/
    /// `GroupMapViewModel.mapViewportSizePt` before the real map view has reported its size via
    /// `GeometryReader` (headless unit tests; the brief real-world window before the first layout
    /// pass). Never used once the render boundary has measured the real viewport.
    public static let unmeasuredViewportSizePt = CGSize(width: 390, height: 844)
}

extension MapRegion {
    /// Translates a pure `MapCameraTarget` decision (specs/010-app-shell-and-screen-ux.md §3.4)
    /// into the concrete viewport `MapRendering`'s `Binding<MapRegion>` consumes. This is the
    /// platform-translation step `MapCameraPolicy` itself deliberately stays agnostic of — same
    /// layering as Android's `GoogleMapRenderer`, which asks `CameraUpdateFactory.newLatLngBounds`
    /// to compute the exact fit against a live view's pixel size. SwiftUI's `Map(coordinateRegion:)`
    /// binding has no equivalent "fit these bounds with N pt of padding" primitive, and there is no
    /// live view size available to this pure translation either, so `.bounds`' `paddingPt` is
    /// approximated with a fixed proportional inflation (`boundsInflationFactor`) rather than an
    /// exact pixel fit — pixel-perfect bounds fitting is a rendering-layer concern the 010 §10 test
    /// checklist explicitly leaves to the review gate, not a unit test.
    ///
    /// `zoom` values (010 §3.4's `SINGLE_POINT_ZOOM`/`DEFAULT_ZOOM`) translate to a span using the
    /// standard slippy-map convention that zoom level *n* covers `360 / 2^n` degrees at the equator
    /// (zoom 0 = the whole world) — a deterministic, pure mapping with no dependency on a live map
    /// view's pixel size; only `.bounds` needs `viewSizePt`.
    ///
    /// **RED (I39, in progress):** `viewSizePt` is threaded in but not yet used — `.bounds` still
    /// grows the box by the retired proportional `boundsInflationFactor`, which is exactly the
    /// non-conformant model specs/010 §3.4's 2026-08-26 amendment forbids. This is the deliberate
    /// failing step: `MapRegionFittingTests`'s new fixed-margin assertions must fail against this
    /// stub before the real conversion lands.
    public init(fitting target: MapCameraTarget, viewSizePt: CGSize) {
        switch target {
        case .defaultRegion(let lat, let lon, let zoom):
            let span = Self.spanDegrees(forZoom: zoom)
            self = MapRegion(centerLat: lat, centerLon: lon, spanLatDelta: span, spanLonDelta: span)
        case .center(let lat, let lon, let zoom):
            let span = Self.spanDegrees(forZoom: zoom)
            self = MapRegion(centerLat: lat, centerLon: lon, spanLatDelta: span, spanLonDelta: span)
        case .bounds(let southLat, let northLat, let westLon, let eastLon, _):
            let centerLat = (southLat + northLat) / 2
            let centerLon = (westLon + eastLon) / 2
            let latSpan = max(northLat - southLat, Self.minimumBoundsSpan) * Self.boundsInflationFactor
            let lonSpan = max(eastLon - westLon, Self.minimumBoundsSpan) * Self.boundsInflationFactor
            self = MapRegion(centerLat: centerLat, centerLon: centerLon, spanLatDelta: latSpan, spanLonDelta: lonSpan)
        }
    }

    /// STUB, pending I39's GREEN step — the retired proportional model kept alive only so this
    /// compiles during RED. Removed once `.bounds` uses `screenSpaceSpan` instead.
    private static let boundsInflationFactor = 1.3
    /// Floor for a `.bounds` span so two nearly-identical-but-distinct points (already guaranteed
    /// distinct by `MapCameraPolicy.target`) still produce a visibly non-zero viewport.
    private static let minimumBoundsSpan = 0.01

    private static func spanDegrees(forZoom zoom: Double) -> Double {
        360.0 / pow(2.0, zoom)
    }
}

/// One family device with a known position (001 §5.2) — `MapMarkerBubble`-ready. Devices with no
/// fix yet (`lat`/`lon` both `nil`) never produce an annotation; they still appear in the roster
/// list instead (rendered by `LiveMapScreen`, not the map layer).
public struct MapAnnotationItem: Identifiable, Equatable {
    public let id: String
    public let lat: Double
    public let lon: Double
    public let initials: String
    public let isStale: Bool
    /// specs/010-app-shell-and-screen-ux.md §3.3/§3.5 (I35) — true for every device belonging to
    /// the currently-selected member, so `MapMarkerBubble(selected:)` renders its distinct state.
    public let isSelected: Bool

    public init(id: String, lat: Double, lon: Double, initials: String, isStale: Bool, isSelected: Bool = false) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.initials = initials
        self.isStale = isStale
        self.isSelected = isSelected
    }
}
