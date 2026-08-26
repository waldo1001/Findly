import Testing
@testable import FindlyKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// specs/010-app-shell-and-screen-ux.md §3.4 — `MapRegion(fitting:viewSizePt:)` translates a pure
/// `MapCameraTarget` decision into the concrete viewport `MapRendering`'s `Binding<MapRegion>`
/// consumes (the platform-translation step `MapCameraPolicy` itself deliberately stays agnostic
/// of, mirroring Android's `GoogleMapRenderer`).
///
/// **Amended 2026-08-26, row I39 (normative):** the `.bounds` padding is a FIXED screen-space
/// margin, not a proportional inflation of the bounding box — a percentage-based inflation is
/// explicitly non-conformant. The tests below assert the RESULTING span against the exact
/// fixed-margin formula, and specifically assert that the span depends on the live viewport size
/// — the one property a proportional model can never have, since it never looks at the viewport at
/// all.
@MainActor
struct MapRegionFittingTests {

    /// A generic non-degenerate viewport for the branches (`.defaultRegion`/`.center`) whose zoom
    /// based span math never consults `viewSizePt` at all.
    private static let genericViewport = CGSize(width: 390, height: 844)

    @Test func defaultRegion_centersOnTheGivenPoint_atAWideSpan() {
        let region = MapRegion(fitting: .defaultRegion(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.defaultZoom), viewSizePt: Self.genericViewport)
        #expect(region.centerLat == 51.0543)
        #expect(region.centerLon == 3.7174)
        // Zoom 4 is a calm, continent-scale default — a wide span, not a close-in one.
        #expect(region.spanLatDelta > 10)
    }

    @Test func center_centersOnTheGivenPoint_atATightSpan() {
        let region = MapRegion(fitting: .center(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.singlePointZoom), viewSizePt: Self.genericViewport)
        #expect(region.centerLat == 51.0543)
        #expect(region.centerLon == 3.7174)
        // Zoom 15 is a close zoom — a tight span, materially tighter than the default's.
        #expect(region.spanLatDelta < 1)
    }

    @Test func bounds_centersOnTheMidpoint_andSpansAtLeastTheRawBoundingBox() {
        let region = MapRegion(
            fitting: .bounds(southLat: 50.85, northLat: 51.20, westLon: 3.20, eastLon: 3.90, paddingPt: MapCameraPolicy.boundsPaddingPt),
            viewSizePt: Self.genericViewport
        )
        #expect(region.centerLat == (50.85 + 51.20) / 2)
        #expect(region.centerLon == (3.20 + 3.90) / 2)
        // The span must be at least the raw bounding box — padding only ever grows it.
        #expect(region.spanLatDelta >= 51.20 - 50.85)
        #expect(region.spanLonDelta >= 3.90 - 3.20)
    }

    @Test func bounds_neverProducesAZeroOrNegativeSpan_forAnAlmostZeroBoundingBox() {
        // MapCameraPolicy.target() never actually emits a near-zero .bounds for two points this
        // close (they'd collapse to .center first) — this proves the translation stays defensive
        // regardless, since a degenerate bounding box would otherwise render an invisible viewport.
        let region = MapRegion(
            fitting: .bounds(southLat: 51.05430, northLat: 51.05431, westLon: 3.71740, eastLon: 3.71741, paddingPt: MapCameraPolicy.boundsPaddingPt),
            viewSizePt: Self.genericViewport
        )
        #expect(region.spanLatDelta > 0)
        #expect(region.spanLonDelta > 0)
    }

    /// specs/010 §3.4 (I39) — the fixed screen-space margin, expressed exactly: the raw bounding
    /// box (1.0° on each axis here), once mapped onto `viewSizePt` points, must be inset by exactly
    /// `paddingPt` on every side. That is `resultSpan == rawSpan * viewportPt / (viewportPt - 2 *
    /// paddingPt)` per axis — NOT `rawSpan * 1.3` (the retired proportional model), which would
    /// give 1.3 on both axes regardless of `viewSizePt` and fail this assertion.
    @Test func bounds_padding_isAFixedScreenSpaceMargin_computedExactly() {
        let viewSizePt = CGSize(width: 400, height: 800)
        let paddingPt = 64.0
        let region = MapRegion(
            fitting: .bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: paddingPt),
            viewSizePt: viewSizePt
        )

        let expectedLatSpan = 1.0 * viewSizePt.height / (viewSizePt.height - 2 * paddingPt)
        let expectedLonSpan = 1.0 * viewSizePt.width / (viewSizePt.width - 2 * paddingPt)

        #expect(abs(region.spanLatDelta - expectedLatSpan) < 1e-9)
        #expect(abs(region.spanLonDelta - expectedLonSpan) < 1e-9)
        // Pin the actual numbers too, so a future refactor that silently reintroduces a constant
        // proportional factor (e.g. 1.3) is caught even if the formula above were copy-pasted
        // verbatim from the implementation.
        #expect(abs(region.spanLatDelta - 800.0 / 672.0) < 1e-9)
        #expect(abs(region.spanLonDelta - 400.0 / 272.0) < 1e-9)
    }

    /// The defining, discriminating property of "fixed screen-space margin" versus "proportional
    /// inflation": the SAME geographic bounding box produces a DIFFERENT span depending on the live
    /// viewport size. A proportional model (the retired `boundsInflationFactor`) never reads the
    /// viewport at all, so this would fail against it — both viewports would produce identically
    /// `rawSpan * 1.3`.
    @Test func bounds_span_dependsOnTheLiveViewportSize_forTheIdenticalBoundingBox() {
        let box = MapCameraTarget.bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: MapCameraPolicy.boundsPaddingPt)

        let smallViewport = MapRegion(fitting: box, viewSizePt: CGSize(width: 400, height: 800))
        let largeViewport = MapRegion(fitting: box, viewSizePt: CGSize(width: 800, height: 1600))

        #expect(smallViewport.spanLatDelta != largeViewport.spanLatDelta)
        #expect(smallViewport.spanLonDelta != largeViewport.spanLonDelta)
        // A fixed number of padding points is a SMALLER relative correction against a larger
        // viewport — the large viewport's span must be proportionally closer to the raw box.
        let rawLatSpan = 1.0
        let smallRatio = smallViewport.spanLatDelta / rawLatSpan
        let largeRatio = largeViewport.spanLatDelta / rawLatSpan
        #expect(largeRatio < smallRatio)
    }

    /// specs/010 §3.4 — a not-yet-measured/degenerate viewport (padding alone would consume the
    /// whole view) MUST NOT produce a negative or infinite span; it degrades to a large-but-finite
    /// one instead.
    @Test func bounds_withADegenerateViewport_neverProducesANegativeOrInfiniteSpan() {
        let region = MapRegion(
            fitting: .bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: MapCameraPolicy.boundsPaddingPt),
            viewSizePt: CGSize(width: 10, height: 10)
        )
        #expect(region.spanLatDelta > 0)
        #expect(region.spanLatDelta.isFinite)
        #expect(region.spanLonDelta > 0)
        #expect(region.spanLonDelta.isFinite)
    }
}
