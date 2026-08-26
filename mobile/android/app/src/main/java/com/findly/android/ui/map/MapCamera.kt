package com.findly.android.ui.map

/**
 * A12 (specs/003-android-client.md §12) — a platform/SDK-agnostic camera decision, deliberately
 * independent of any `com.google.android.gms.maps.model` type so this logic is unit-testable on
 * the plain JVM without an Android/Maps runtime (mirrors iOS's provider-agnostic `MapRegion`,
 * specs/004-ios-client.md's `MapModels.swift`). The real Google Maps `CameraUpdate`/`LatLngBounds`
 * translation only happens in `GoogleMapRenderer`, which needs a live `GoogleMap` view.
 */
sealed class MapCameraTarget {
    /** No marker has a known position yet — a calm, zoomed-out default rather than the (0, 0)
     * "null island" a naive empty-bounds calculation would produce. */
    data class Default(val lat: Double, val lon: Double, val zoom: Float) : MapCameraTarget()

    /** Exactly one distinct marker position (including "every marker is at the same spot") —
     * centering beats fitting a zero-area bounds, which some map SDKs render inconsistently
     * (typically clamped to the SDK's max zoom). */
    data class Center(val lat: Double, val lon: Double, val zoom: Float) : MapCameraTarget()

    /** Two or more distinct marker positions — fit them all with padding. Only the geographic
     * corners are decided here; the actual zoom level is computed by the Maps SDK's own
     * `CameraUpdateFactory.newLatLngBounds`, which needs the real view's pixel size.
     *
     * [paddingDp] (specs/010-app-shell-and-screen-ux.md §3.4, normative) is density-aware —
     * `GoogleMapRenderer` converts it to px via the real view's [androidx.compose.ui.unit.Density]
     * immediately before calling `CameraUpdateFactory.newLatLngBounds`, since that's the only
     * place a real pixel density exists; this pure module stays SDK/density-agnostic. Replaces
     * the previous raw `paddingPx = 128`, which rendered a different physical inset per device. */
    data class Bounds(
        val southLat: Double,
        val northLat: Double,
        val westLon: Double,
        val eastLon: Double,
        val paddingDp: Float,
    ) : MapCameraTarget()
}

object MapCamera {
    /** Ghent, Belgium — the same sample coordinate used throughout specs/001 and the Compose
     * previews; matches iOS's `MapRegion.findlyDefault` (specs/004-ios-client.md) so both apps
     * open on the same calm default before any family location has ever been reported. */
    const val DEFAULT_LAT = 51.0543
    const val DEFAULT_LON = 3.7174
    const val DEFAULT_ZOOM = 4f
    const val SINGLE_POINT_ZOOM = 15f

    const val BOUNDS_PADDING_DP = 64f

    /**
     * [points] are `lat to lon` pairs for every device/member with a known position — callers
     * MUST already have filtered out `hasLocation == false` entries (001 §5.2/§12.10's
     * "no location yet" devices carry no coordinate to plot).
     */
    fun target(points: List<Pair<Double, Double>>): MapCameraTarget {
        val distinct = points.distinct()
        return when (distinct.size) {
            0 -> MapCameraTarget.Default(DEFAULT_LAT, DEFAULT_LON, DEFAULT_ZOOM)
            1 -> MapCameraTarget.Center(distinct[0].first, distinct[0].second, SINGLE_POINT_ZOOM)
            else -> {
                val lats = distinct.map { it.first }
                val lons = distinct.map { it.second }
                MapCameraTarget.Bounds(
                    southLat = lats.min(),
                    northLat = lats.max(),
                    westLon = lons.min(),
                    eastLon = lons.max(),
                    paddingDp = BOUNDS_PADDING_DP,
                )
            }
        }
    }
}
