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

    // MARK: - Occlusion model (added 2026-09-07, row I49 — specs/010 §3.4)

    /// Screen row (points from the top, north-up) a latitude maps to, given a fitted `MapRegion`
    /// rendered over a viewport `viewportHeightPt` tall — the SAME projection MapKit itself uses
    /// for a plain `MKCoordinateRegion`: the region's `centerLat` always lands at the exact
    /// vertical center of the FULL viewport, and `spanLatDelta` always covers the FULL viewport
    /// top-to-bottom, regardless of any sheet drawn on top of it (the sheet is a separate view,
    /// not a smaller map viewport). This is the one honest way to test "does the fitted box
    /// actually clear the sheet" without a live MapKit view: project the real geographic edges
    /// through the region MapKit would be handed, exactly as MapKit itself would render them.
    private static func row(forLat lat: Double, region: MapRegion, viewportHeightPt: Double) -> Double {
        viewportHeightPt / 2 - (lat - region.centerLat) / region.spanLatDelta * viewportHeightPt
    }

    /// specs/010 §3.4 "Occlusion model" (I49, normative) — the defect this row exists to fix: a
    /// geographically spread family's fit-all previously placed members underneath the sheet. This
    /// proves the FRAMING, not just the inset arithmetic: given a sheet covering the bottom 200pt
    /// of an 800pt-tall viewport, both the north AND south edges of the raw bounding box must land
    /// strictly above row 600 (where the sheet begins) — with the same 64pt margin from the
    /// REDUCED area's edges the padding model already guarantees against the full viewport.
    @Test func bounds_withSheetOcclusion_fitsTheRawBoxAboveTheSheet_notUnderneathIt() {
        let viewSizePt = CGSize(width: 400, height: 800)
        let sheetHeightPt = 200.0
        let paddingPt = MapCameraPolicy.boundsPaddingPt
        let region = MapRegion(
            fitting: .bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: paddingPt),
            viewSizePt: viewSizePt,
            sheetHeightPt: sheetHeightPt
        )

        let northRow = Self.row(forLat: 51.0, region: region, viewportHeightPt: viewSizePt.height)
        let southRow = Self.row(forLat: 50.0, region: region, viewportHeightPt: viewSizePt.height)
        let sheetTopRow = viewSizePt.height - sheetHeightPt

        // The top margin is unaffected by the sheet (it occludes only the bottom).
        #expect(abs(northRow - paddingPt) < 1e-6)
        // The bottom edge clears the sheet by exactly the same 64pt margin, measured from the
        // REDUCED area's own bottom edge (the top of the sheet) — not from the full viewport's
        // bottom edge, which is what the pre-I49 defect did.
        #expect(abs(southRow - (sheetTopRow - paddingPt)) < 1e-6)
        // The actual bug this row exists to catch: the south edge must land strictly above where
        // the sheet begins, with room to spare.
        #expect(southRow < sheetTopRow)
    }

    /// specs/010 §3.4 — "a viewport inset, not a padding change": the sheet occludes only the
    /// bottom of the screen, so the horizontal (longitude) fit is untouched by `sheetHeightPt`.
    @Test func bounds_withSheetOcclusion_leavesTheLongitudeFitUnchanged() {
        let viewSizePt = CGSize(width: 400, height: 800)
        let paddingPt = MapCameraPolicy.boundsPaddingPt
        let target = MapCameraTarget.bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: paddingPt)

        let withoutSheet = MapRegion(fitting: target, viewSizePt: viewSizePt, sheetHeightPt: 0)
        let withSheet = MapRegion(fitting: target, viewSizePt: viewSizePt, sheetHeightPt: 200)

        #expect(withoutSheet.centerLon == withSheet.centerLon)
        #expect(withoutSheet.spanLonDelta == withSheet.spanLonDelta)
    }

    /// specs/010 §3.4 — a zero sheet height (or omitting the parameter entirely) MUST be byte-for-
    /// byte identical to the pre-I49 formula: no sheet means no inset, so this must not even
    /// introduce floating-point drift into the existing I39 padding-model guarantees.
    @Test func bounds_withZeroSheetHeight_isIdenticalToOmittingTheParameter() {
        let viewSizePt = CGSize(width: 400, height: 800)
        let target = MapCameraTarget.bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: MapCameraPolicy.boundsPaddingPt)

        let omitted = MapRegion(fitting: target, viewSizePt: viewSizePt)
        let explicitZero = MapRegion(fitting: target, viewSizePt: viewSizePt, sheetHeightPt: 0)

        #expect(omitted == explicitZero)
        #expect(explicitZero.centerLat == (50.0 + 51.0) / 2)
    }

    /// specs/010 §3.4 — a sheet reported taller than the viewport itself (a not-yet-measured
    /// height, or a transient layout glitch) MUST NOT produce a negative or infinite span, exactly
    /// like the pre-existing degenerate-viewport guard.
    @Test func bounds_withASheetTallerThanTheViewport_neverProducesANegativeOrInfiniteSpan() {
        let region = MapRegion(
            fitting: .bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: MapCameraPolicy.boundsPaddingPt),
            viewSizePt: CGSize(width: 400, height: 800),
            sheetHeightPt: 5000
        )
        #expect(region.spanLatDelta > 0)
        #expect(region.spanLatDelta.isFinite)
        #expect(region.centerLat.isFinite)
    }

    /// A detent change alone MUST NOT move the camera (specs/010 §3.4, normative) — this is
    /// enforced at the `MapCameraPolicy`/view-model layer (never re-emitting a command on a detent
    /// change), not here. This test instead pins the OTHER half of that contract at the fitting
    /// layer: fit-all re-invoked with a DIFFERENT `sheetHeightPt` (i.e. the detent changed between
    /// two explicit fit-all taps) DOES produce a different region — proving the fitting math is
    /// actually sheet-aware, so the "tap fit-all again after a detent drag" workaround the spec
    /// prescribes actually works.
    @Test func bounds_refitAfterADetentChange_reframesAgainstTheNewSheetHeight() {
        let viewSizePt = CGSize(width: 400, height: 800)
        let target = MapCameraTarget.bounds(southLat: 50.0, northLat: 51.0, westLon: 3.0, eastLon: 4.0, paddingPt: MapCameraPolicy.boundsPaddingPt)

        let atMinimized = MapRegion(fitting: target, viewSizePt: viewSizePt, sheetHeightPt: 160)
        let atExpanded = MapRegion(fitting: target, viewSizePt: viewSizePt, sheetHeightPt: 700)

        #expect(atMinimized.centerLat != atExpanded.centerLat)
        #expect(atMinimized.spanLatDelta != atExpanded.spanLatDelta)
    }
}
