package com.findly.android.ui.map

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A12 (specs/003-android-client.md §12) — [MapCamera.target] is the platform/SDK-agnostic camera
 * decision (mirrors iOS's provider-agnostic `MapRegion`, specs/004-ios-client.md's
 * `MapModels.swift`): pure JVM logic, no Android/Maps runtime needed. The real
 * `CameraUpdateFactory`/`LatLngBounds` translation only happens in `GoogleMapRenderer`, which
 * needs a live `GoogleMap` view and can't be exercised here (no emulator in this environment).
 */
class MapCameraTest {

    @Test
    fun `no points yields the calm zoomed-out default, never null island`() {
        val target = MapCamera.target(emptyList())
        assertEquals(
            MapCameraTarget.Default(MapCamera.DEFAULT_LAT, MapCamera.DEFAULT_LON, MapCamera.DEFAULT_ZOOM),
            target,
        )
    }

    @Test
    fun `a single point centers on it at a close zoom`() {
        val target = MapCamera.target(listOf(51.0543 to 3.7174))
        assertEquals(MapCameraTarget.Center(51.0543, 3.7174, MapCamera.SINGLE_POINT_ZOOM), target)
    }

    @Test
    fun `duplicate identical points collapse to Center, not a zero-area Bounds`() {
        val target = MapCamera.target(listOf(51.0543 to 3.7174, 51.0543 to 3.7174, 51.0543 to 3.7174))
        assertEquals(MapCameraTarget.Center(51.0543, 3.7174, MapCamera.SINGLE_POINT_ZOOM), target)
    }

    @Test
    fun `two distinct points yield Bounds spanning both, regardless of input order`() {
        val target = MapCamera.target(listOf(51.20 to 3.90, 50.85 to 3.20)) as MapCameraTarget.Bounds
        assertEquals(50.85, target.southLat, 0.0)
        assertEquals(51.20, target.northLat, 0.0)
        assertEquals(3.20, target.westLon, 0.0)
        assertEquals(3.90, target.eastLon, 0.0)
        assertEquals(MapCamera.BOUNDS_PADDING_PX, target.paddingPx)
    }

    @Test
    fun `bounds correctly spans negative (southern-western) coordinates`() {
        val target = MapCamera.target(listOf(-33.87 to 151.21, -37.81 to 144.96)) as MapCameraTarget.Bounds
        assertEquals(-37.81, target.southLat, 0.0)
        assertEquals(-33.87, target.northLat, 0.0)
        assertEquals(144.96, target.westLon, 0.0)
        assertEquals(151.21, target.eastLon, 0.0)
    }

    @Test
    fun `three or more distinct points still yield one Bounds covering every point`() {
        val target = MapCamera.target(listOf(51.0 to 3.5, 51.2 to 3.9, 50.9 to 3.6)) as MapCameraTarget.Bounds
        assertEquals(50.9, target.southLat, 0.0)
        assertEquals(51.2, target.northLat, 0.0)
        assertEquals(3.5, target.westLon, 0.0)
        assertEquals(3.9, target.eastLon, 0.0)
    }

    @Test
    fun `a point already filtered to have a location never collapses distinct-but-close coordinates`() {
        // Two members standing a few metres apart must not be treated as the same point.
        val target = MapCamera.target(listOf(51.05430 to 3.71740, 51.05431 to 3.71741)) as MapCameraTarget.Bounds
        assertEquals(51.05430, target.southLat, 0.0)
        assertEquals(51.05431, target.northLat, 0.0)
    }
}
