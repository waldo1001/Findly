import CoreGraphics
import Foundation
import SwiftUI

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
    /// SDK's real camera steps here. 010 §10 does not carve this specific case out by name — its
    /// actual text reserves the review gate for "rename-row alignment and full-bleed layout"
    /// (visual, per the design-seam convention). This falls into that SAME category by the same
    /// logic (visual, sub-perceptual at normal zoom, no live-view-size unit test can assert
    /// against a real rendered frame) rather than under an explicit named carve-out — the review
    /// gate is where it is caught, not a unit test.
    ///
    /// `zoom` values (010 §3.4's `SINGLE_POINT_ZOOM`/`DEFAULT_ZOOM`) translate to a span using the
    /// standard slippy-map convention that zoom level *n* covers `360 / 2^n` degrees at the equator
    /// (zoom 0 = the whole world) — a deterministic, pure mapping with no dependency on a live map
    /// view's pixel size; only `.bounds` needs `viewSizePt`.
    ///
    /// **Occlusion model (added 2026-09-07, row I49 — normative).** `sheetHeightPt` is the roster
    /// sheet's height in points AT THE MOMENT the fit is computed (the caller — `LiveMapViewModel`/
    /// `GroupMapViewModel` — reads whatever detent is current when the triggering action fires; a
    /// later detent drag does not retroactively move the camera, per §3.4's "detent change MUST
    /// NOT move the camera" rule). Only the `.bounds` case is affected — `.center`/`.defaultRegion`
    /// aren't a "fit", so occlusion doesn't apply to them, matching the spec's "the bounds-fit MUST
    /// be computed against the map area not covered by the sheet" wording. Only the LATITUDE axis
    /// is inset: the sheet occludes the bottom of the screen, not the sides, so longitude fitting
    /// is unchanged regardless of `sheetHeightPt` (proven by
    /// `bounds_withSheetOcclusion_leavesTheLongitudeFitUnchanged`).
    ///
    /// This is a **viewport inset, not a padding change** (§3.4): `paddingPt` stays exactly the
    /// fixed screen-space margin I39 defined, measured from the edges of the REDUCED area (full
    /// height minus `sheetHeightPt`) instead of the full viewport. Concretely: degrees-per-point is
    /// computed against the reduced area (`rawLatSpan / (usableHeightPt - 2 * paddingPt)`, the same
    /// shape `screenSpaceSpan` already uses, just with `usableHeightPt` in place of the full
    /// height), then `centerLat` is shifted north of the raw bounding box's true geographic
    /// midpoint by exactly enough that — once that degrees-per-point is rendered over the FULL
    /// viewport height (a `MapRegion`'s `spanLatDelta` always covers the full view, since the sheet
    /// is a separate view drawn on top, not a smaller map viewport) — the box's north edge sits
    /// `paddingPt` below the viewport's top edge and its south edge sits `paddingPt` above the
    /// sheet's top edge. When `sheetHeightPt == 0` this reduces ALGEBRAICALLY (not just
    /// numerically) to the pre-I49 formula, so it is only invoked when there is actually a sheet to
    /// avoid — see `bounds_withZeroSheetHeight_isIdenticalToOmittingTheParameter`, which pins
    /// `centerLat` to the plain `(south + north) / 2` average via `==`, not a tolerance.
    public init(fitting target: MapCameraTarget, viewSizePt: CGSize, sheetHeightPt: Double = 0) {
        switch target {
        case .defaultRegion(let lat, let lon, let zoom):
            let span = Self.spanDegrees(forZoom: zoom)
            self = MapRegion(centerLat: lat, centerLon: lon, spanLatDelta: span, spanLonDelta: span)
        case .center(let lat, let lon, let zoom):
            let span = Self.spanDegrees(forZoom: zoom)
            self = MapRegion(centerLat: lat, centerLon: lon, spanLatDelta: span, spanLonDelta: span)
        case .bounds(let southLat, let northLat, let westLon, let eastLon, let paddingPt):
            let centerLon = (westLon + eastLon) / 2
            let rawLatSpan = max(northLat - southLat, Self.minimumBoundsSpan)
            let rawLonSpan = max(eastLon - westLon, Self.minimumBoundsSpan)
            let lonSpan = Self.screenSpaceSpan(rawSpan: rawLonSpan, viewportPt: viewSizePt.width, paddingPt: paddingPt)

            let centerLat: Double
            let latSpan: Double
            if sheetHeightPt > 0 {
                (centerLat, latSpan) = Self.sheetAwareLatFit(
                    northLat: northLat, rawLatSpan: rawLatSpan,
                    viewportHeightPt: viewSizePt.height, sheetHeightPt: sheetHeightPt, paddingPt: paddingPt
                )
            } else {
                centerLat = (southLat + northLat) / 2
                latSpan = Self.screenSpaceSpan(rawSpan: rawLatSpan, viewportPt: viewSizePt.height, paddingPt: paddingPt)
            }
            self = MapRegion(centerLat: centerLat, centerLon: centerLon, spanLatDelta: latSpan, spanLonDelta: lonSpan)
        }
    }

    /// specs/010 §3.4 (I49) — the occlusion-aware latitude fit: degrees-per-point is computed
    /// against the area NOT covered by the sheet (`usableHeightPt`), then `centerLat` is solved so
    /// that, rendered at that degrees-per-point over the FULL viewport, the raw box's north edge
    /// lands `paddingPt` from the top and its south edge lands `paddingPt` above the sheet's top
    /// edge. See this initializer's header doc for the full derivation.
    private static func sheetAwareLatFit(
        northLat: Double, rawLatSpan: Double, viewportHeightPt: Double, sheetHeightPt: Double, paddingPt: Double
    ) -> (centerLat: Double, latSpan: Double) {
        let usableHeightPt = max(viewportHeightPt - sheetHeightPt, 1)
        let availablePt = max(usableHeightPt - 2 * paddingPt, 1)
        let degreesPerPoint = rawLatSpan / availablePt
        let centerLat = northLat - degreesPerPoint * (viewportHeightPt / 2 - paddingPt)
        let latSpan = degreesPerPoint * viewportHeightPt
        return (centerLat, latSpan)
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

/// specs/010-app-shell-and-screen-ux.md §3.4 (I45 fix — "app shell & screen UX regression: dead
/// sheet space, notch-clashing chrome"). I39 made the `LiveMapScreen`/`GroupMapScreen`
/// `GeometryReader` itself `.ignoresSafeArea()` so `geometry.size` would report the true
/// full-bleed extent instead of the safe-area-constrained one — but `.ignoresSafeArea()` on the
/// reader pulls its ENTIRE subtree out of the safe area, including `topChrome` (drawn under the
/// Dynamic Island/notch, untappable) and the `FindlyBottomSheet` chained after it (sized against a
/// frame that overruns the home indicator, producing dead space at the bottom of every detent).
///
/// The fix: the reader goes back to respecting the safe area (so `topChrome` and the sheet lay out
/// correctly again), and the full-bleed size is recovered arithmetically instead.
/// `GeometryProxy.safeAreaInsets` reports exactly the margins SwiftUI subtracted off
/// `geometry.size` to produce the constrained value, so adding them back is lossless — this
/// recovers the identical full-bleed size `.ignoresSafeArea()` on the reader used to produce,
/// without changing anything about how the subtree itself is laid out. Kept as a free function
/// (not folded into a view) purely so the arithmetic is unit-testable independent of any live view
/// hierarchy (`MapViewportBleedingTests`) — `swift test` has no `GeometryReader` to instantiate.
public enum MapViewport {
    public static func bled(constrained size: CGSize, safeAreaInsets insets: EdgeInsets) -> CGSize {
        CGSize(
            width: size.width + insets.leading + insets.trailing,
            height: size.height + insets.top + insets.bottom
        )
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
