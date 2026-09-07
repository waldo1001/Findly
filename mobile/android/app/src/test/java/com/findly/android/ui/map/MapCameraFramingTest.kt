package com.findly.android.ui.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * specs/010-app-shell-and-screen-ux.md §3.4 "Occlusion model" (added 2026-09-07, row I49,
 * normative) — [MapCameraFraming.widenForSheetOcclusion] is the pure, SDK-agnostic half of the fix
 * (mirrors iOS's `MapRegion(fitting:viewSizePt:sheetHeightPt:)`): it widens/shifts a raw
 * `.Bounds` target's latitude edges so that handing the WIDENED bounds, unchanged, to Google
 * Maps' own `CameraUpdateFactory.newLatLngBounds(bounds, paddingPx)` — which fits bounds
 * symmetrically, centered, within the FULL view — renders the ORIGINAL bounds entirely within the
 * area above the roster sheet, with the same 64dp margin measured from that reduced area's edges.
 * [GoogleMapRenderer] cannot be exercised in a plain JVM test (no live `GoogleMap`/emulator here,
 * same limitation `MapCameraTest`'s header doc already notes), so this test proves the actual
 * FRAMING by reimplementing the SDK's own documented `newLatLngBounds` contract as a pure
 * projection — not just the inset arithmetic — exactly like iOS's `MapRegionFittingTests` does for
 * `MapRegion`.
 */
class MapCameraFramingTest {

    /** Simulates exactly what `CameraUpdateFactory.newLatLngBounds(bounds, paddingPx)` does per
     * its documented contract: centers the camera at `bounds`' own centroid, and computes the
     * zoom/degrees-per-pixel such that `bounds` (inset by `paddingPx`) fits within the FULL
     * `viewportHeightPx`. Returns the screen row (pixels from the top, north-up) `lat` maps to
     * once that fit is applied. */
    private fun rowAfterSdkFit(lat: Double, bounds: MapCameraTarget.Bounds, viewportHeightPx: Float, paddingPx: Float): Float {
        val rawSpan = bounds.northLat - bounds.southLat
        val centerLat = (bounds.southLat + bounds.northLat) / 2
        val dpp = rawSpan / (viewportHeightPx - 2 * paddingPx)
        return (viewportHeightPx / 2 - ((lat - centerLat) / dpp)).toFloat()
    }

    @Test
    fun `zero sheet height is a no-op, byte-for-byte`() {
        val bounds = MapCameraTarget.Bounds(southLat = 50.0, northLat = 51.0, westLon = 3.0, eastLon = 4.0, paddingDp = 64f)
        val widened = MapCameraFraming.widenForSheetOcclusion(
            bounds = bounds, viewportHeightPx = 800f, sheetHeightPx = 0f, paddingPx = 128f,
        )
        assertEquals(bounds, widened)
    }

    @Test
    fun `longitude is untouched by sheet occlusion`() {
        val bounds = MapCameraTarget.Bounds(southLat = 50.0, northLat = 51.0, westLon = 3.0, eastLon = 4.0, paddingDp = 64f)
        val widened = MapCameraFraming.widenForSheetOcclusion(
            bounds = bounds, viewportHeightPx = 800f, sheetHeightPx = 200f, paddingPx = 128f,
        )
        assertEquals(bounds.westLon, widened.westLon, 0.0)
        assertEquals(bounds.eastLon, widened.eastLon, 0.0)
        assertEquals(bounds.paddingDp, widened.paddingDp)
    }

    /**
     * The defect this row exists to fix: a geographically spread family's fit-all previously
     * placed members underneath the sheet. Proves the RESULTING FRAMING (not just the inset
     * arithmetic) by feeding the widened bounds through a pure reimplementation of the SDK's own
     * `newLatLngBounds` contract, then checking the ORIGINAL (unwidened) box's north/south edges
     * land within the area above a sheet covering the bottom 200px of an 800px-tall viewport, with
     * the same paddingPx margin from each edge of that reduced area.
     */
    @Test
    fun `widened bounds fit the raw box above the sheet, not underneath it`() {
        val paddingPx = 128f
        val viewportHeightPx = 800f
        val sheetHeightPx = 200f
        val bounds = MapCameraTarget.Bounds(southLat = 50.0, northLat = 51.0, westLon = 3.0, eastLon = 4.0, paddingDp = 64f)

        val widened = MapCameraFraming.widenForSheetOcclusion(bounds, viewportHeightPx, sheetHeightPx, paddingPx)

        val northRow = rowAfterSdkFit(bounds.northLat, widened, viewportHeightPx, paddingPx)
        val southRow = rowAfterSdkFit(bounds.southLat, widened, viewportHeightPx, paddingPx)
        val sheetTopRow = viewportHeightPx - sheetHeightPx

        assertTrue("north edge should keep the ${paddingPx}px top margin, was $northRow", abs(northRow - paddingPx) < 0.5f)
        assertTrue(
            "south edge should sit ${paddingPx}px above the sheet (row ${sheetTopRow - paddingPx}), was $southRow",
            abs(southRow - (sheetTopRow - paddingPx)) < 0.5f,
        )
        assertTrue("south edge ($southRow) must land strictly above where the sheet begins ($sheetTopRow)", southRow < sheetTopRow)
    }

    @Test
    fun `a sheet taller than the viewport never produces a negative or infinite span`() {
        val bounds = MapCameraTarget.Bounds(southLat = 50.0, northLat = 51.0, westLon = 3.0, eastLon = 4.0, paddingDp = 64f)
        val widened = MapCameraFraming.widenForSheetOcclusion(
            bounds = bounds, viewportHeightPx = 800f, sheetHeightPx = 5000f, paddingPx = 128f,
        )
        val span = widened.northLat - widened.southLat
        assertTrue(span > 0)
        assertTrue(span.isFinite())
        assertTrue(widened.northLat.isFinite())
        assertTrue(widened.southLat.isFinite())
    }

    @Test
    fun `re-widening with a different sheet height produces a different result`() {
        val bounds = MapCameraTarget.Bounds(southLat = 50.0, northLat = 51.0, westLon = 3.0, eastLon = 4.0, paddingDp = 64f)
        val atMinimized = MapCameraFraming.widenForSheetOcclusion(bounds, 800f, 160f, 128f)
        val atExpanded = MapCameraFraming.widenForSheetOcclusion(bounds, 800f, 700f, 128f)
        assertNotEquals(atMinimized, atExpanded)
    }
}
