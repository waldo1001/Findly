import Testing
@testable import FindlyKit

/// specs/010-app-shell-and-screen-ux.md §3.4 — `MapRegion(fitting:)` translates a pure
/// `MapCameraTarget` decision into the concrete viewport `MapRendering`'s `Binding<MapRegion>`
/// consumes (the platform-translation step `MapCameraPolicy` itself deliberately stays agnostic
/// of, mirroring Android's `GoogleMapRenderer`).
@MainActor
struct MapRegionFittingTests {

    @Test func defaultRegion_centersOnTheGivenPoint_atAWideSpan() {
        let region = MapRegion(fitting: .defaultRegion(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.defaultZoom))
        #expect(region.centerLat == 51.0543)
        #expect(region.centerLon == 3.7174)
        // Zoom 4 is a calm, continent-scale default — a wide span, not a close-in one.
        #expect(region.spanLatDelta > 10)
    }

    @Test func center_centersOnTheGivenPoint_atATightSpan() {
        let region = MapRegion(fitting: .center(lat: 51.0543, lon: 3.7174, zoom: MapCameraPolicy.singlePointZoom))
        #expect(region.centerLat == 51.0543)
        #expect(region.centerLon == 3.7174)
        // Zoom 15 is a close zoom — a tight span, materially tighter than the default's.
        #expect(region.spanLatDelta < 1)
    }

    @Test func bounds_centersOnTheMidpoint_andSpansAtLeastTheRawBoundingBox() {
        let region = MapRegion(fitting: .bounds(southLat: 50.85, northLat: 51.20, westLon: 3.20, eastLon: 3.90, paddingPt: MapCameraPolicy.boundsPaddingPt))
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
        let region = MapRegion(fitting: .bounds(southLat: 51.05430, northLat: 51.05431, westLon: 3.71740, eastLon: 3.71741, paddingPt: MapCameraPolicy.boundsPaddingPt))
        #expect(region.spanLatDelta > 0)
        #expect(region.spanLonDelta > 0)
    }
}
