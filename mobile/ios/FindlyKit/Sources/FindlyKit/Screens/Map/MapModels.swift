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
    /// to compute the exact fit against a live view's pixel size.
    ///
    /// **Amended 2026-08-26, row I39 (normative).** The `.bounds` `paddingPt` is a FIXED
    /// screen-space margin, not a proportional inflation of the bounding box — a percentage-based
    /// inflation is explicitly non-conformant (it let this platform and Android frame the same
    /// family at materially different zoom while both nominally honored "64pt of padding").
    /// `viewSizePt` is the live map viewport's size in points, threaded in from the render boundary
    /// (`LiveMapScreen`/`GroupMapScreen`'s `GeometryReader`, kept current on
    /// `LiveMapViewModel`/`GroupMapViewModel.mapViewportSizePt`) — this mirrors Android resolving
    /// `LocalDensity` at `GoogleMapRenderer` rather than in the pure `MapCamera`/`MapCameraPolicy`
    /// decision layer, so this initializer itself stays pure and unit-testable: given the same
    /// `target` and `viewSizePt`, it always returns the same region.
    ///
    /// Per axis, the span is scaled so the raw bounding box — once mapped onto `viewSizePt` points —
    /// is inset by exactly `paddingPt` on every side:
    /// `rawSpan / resultSpan == (viewportPt - 2 * paddingPt) / viewportPt`, i.e.
    /// `resultSpan == rawSpan * viewportPt / (viewportPt - 2 * paddingPt)`. This is the same
    /// "fit bounds, leave N points of margin" contract `CameraUpdateFactory.newLatLngBounds(bounds,
    /// paddingPx)` honors — computed here in plain lat/lon degrees (this type's whole point, per its
    /// header doc, is staying decoupled from `MKCoordinateRegion`/MapKit's own Mercator projection),
    /// not Android's Mercator-projected pixel space. That is the one place exact cross-platform
    /// parity is NOT achievable: an equirectangular delta and a Mercator-projected fit diverge
    /// slightly away from the equator, and neither platform's zoom is quantized/clamped to its map
    /// SDK's real camera steps here — 010 §10 explicitly defers pixel-exact fitting to the review
    /// gate, not a unit test.
    ///
    /// `zoom` values (010 §3.4's `SINGLE_POINT_ZOOM`/`DEFAULT_ZOOM`) translate to a span using the
    /// standard slippy-map convention that zoom level *n* covers `360 / 2^n` degrees at the equator
    /// (zoom 0 = the whole world) — a deterministic, pure mapping with no dependency on a live map
    /// view's pixel size; only `.bounds` needs `viewSizePt`.
    public init(fitting target: MapCameraTarget, viewSizePt: CGSize) {
        switch target {
        case .defaultRegion(let lat, let lon, let zoom):
            let span = Self.spanDegrees(forZoom: zoom)
            self = MapRegion(centerLat: lat, centerLon: lon, spanLatDelta: span, spanLonDelta: span)
        case .center(let lat, let lon, let zoom):
            let span = Self.spanDegrees(forZoom: zoom)
            self = MapRegion(centerLat: lat, centerLon: lon, spanLatDelta: span, spanLonDelta: span)
        case .bounds(let southLat, let northLat, let westLon, let eastLon, let paddingPt):
            let centerLat = (southLat + northLat) / 2
            let centerLon = (westLon + eastLon) / 2
            let rawLatSpan = max(northLat - southLat, Self.minimumBoundsSpan)
            let rawLonSpan = max(eastLon - westLon, Self.minimumBoundsSpan)
            let latSpan = Self.screenSpaceSpan(rawSpan: rawLatSpan, viewportPt: viewSizePt.height, paddingPt: paddingPt)
            let lonSpan = Self.screenSpaceSpan(rawSpan: rawLonSpan, viewportPt: viewSizePt.width, paddingPt: paddingPt)
            self = MapRegion(centerLat: centerLat, centerLon: centerLon, spanLatDelta: latSpan, spanLonDelta: lonSpan)
        }
    }

    /// Floor for a `.bounds` span so two nearly-identical-but-distinct points (already guaranteed
    /// distinct by `MapCameraPolicy.target`) still produce a visibly non-zero viewport.
    private static let minimumBoundsSpan = 0.01

    /// specs/010 §3.4 (amended 2026-08-26, row I39) — the fixed-screen-space-margin conversion:
    /// scales `rawSpan` (degrees) up so that, once mapped onto `viewportPt` points, `rawSpan` is
    /// inset by exactly `paddingPt` on each side. Guards a not-yet-measured or degenerate viewport
    /// (`viewportPt <= 2 * paddingPt`, e.g. before `GeometryReader` first reports, or a padding
    /// larger than the view itself) by flooring the available space to 1pt, so this never divides
    /// by zero or returns a negative span — it degrades to a large-but-finite one instead.
    private static func screenSpaceSpan(rawSpan: Double, viewportPt: Double, paddingPt: Double) -> Double {
        let availablePt = max(viewportPt - 2 * paddingPt, 1)
        return rawSpan * viewportPt / availablePt
    }

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
