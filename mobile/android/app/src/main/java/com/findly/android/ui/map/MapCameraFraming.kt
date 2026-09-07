package com.findly.android.ui.map

/**
 * specs/010-app-shell-and-screen-ux.md §3.4 "Occlusion model" (added 2026-09-07, row I49,
 * normative) — the pure, SDK-agnostic half of the fix, mirroring iOS's `MapRegion(fitting:
 * viewSizePt:sheetHeightPt:)`. [MapCamera.target] and [GoogleMapRenderer] are unchanged: this
 * widens/shifts a raw [MapCameraTarget.Bounds]' latitude edges so that handing the WIDENED bounds,
 * unchanged, to Google Maps' own `CameraUpdateFactory.newLatLngBounds(bounds, paddingPx)` — which
 * fits `bounds` symmetrically, centered at its own centroid, within the FULL view — renders the
 * ORIGINAL (unwidened) bounds entirely within the area above the roster sheet, with the same
 * `paddingPx` margin measured from that reduced area's edges instead of the full viewport.
 *
 * Longitude (west/east) is untouched — the sheet occludes only the bottom of the screen, never the
 * sides, matching iOS's identical "only the latitude axis is inset" decision.
 *
 * This is a **viewport inset, not a padding change** (§3.4): `paddingDp`/`paddingPx` stays exactly
 * the fixed screen-space margin [MapCamera.BOUNDS_PADDING_DP] already defines — only the rectangle
 * it's measured against changes. [GoogleMapRenderer] calls this immediately before constructing the
 * `LatLngBounds` it hands to `newLatLngBounds`, so the SDK's own padding/zoom math needs no change
 * at all; only its INPUT is pre-adjusted here, in plain, JVM-testable Kotlin (this file has no
 * Android/Maps runtime dependency, exactly like [MapCamera]/[MapCameraPolicy] — see those types'
 * header docs for why that matters: "no emulator in this environment").
 */
object MapCameraFraming {

    /**
     * Derivation: `CameraUpdateFactory.newLatLngBounds(bounds, paddingPx)` centers the camera at
     * `bounds`' own centroid and computes degrees-per-pixel (`dpp`) as
     * `(bounds.span) / (viewportHeightPx - 2 * paddingPx)`, over the FULL `viewportHeightPx`
     * (the sheet is a separate view drawn on top, not a smaller map viewport, so the SDK never
     * knows about it). We want the ORIGINAL (unwidened) box's north edge to land `paddingPx` below
     * the viewport's top edge, and its south edge to land `paddingPx` above the sheet's top edge
     * (`viewportHeightPx - sheetHeightPx`). Solving those two row equations for a widened bounds'
     * `centerLat`/`span` (full algebra in the equivalent iOS derivation, `MapModels.swift`'s
     * `sheetAwareLatFit`) gives:
     *
     * `dppTarget = rawLatSpan / (usableHeightPx - 2 * paddingPx)`, where
     * `usableHeightPx = viewportHeightPx - sheetHeightPx`
     * `centerLat = bounds.northLat - dppTarget * (viewportHeightPx / 2 - paddingPx)`
     * `widenedSpan = dppTarget * (viewportHeightPx - 2 * paddingPx)` — NOT `dppTarget *
     * viewportHeightPx`, because this span is fed BACK through the SDK's own `newLatLngBounds`,
     * which will itself divide by `(viewportHeightPx - 2 * paddingPx)` to recover `dppTarget`.
     *
     * When `sheetHeightPx <= 0` this reduces algebraically (not just numerically) to the original
     * `bounds` unchanged — see `MapCameraFramingTest`'s "zero sheet height is a no-op" test — so a
     * caller can always call this unconditionally without a separate "is there a sheet" branch.
     */
    fun widenForSheetOcclusion(
        bounds: MapCameraTarget.Bounds,
        viewportHeightPx: Float,
        sheetHeightPx: Float,
        paddingPx: Float,
    ): MapCameraTarget.Bounds {
        if (sheetHeightPx <= 0f || viewportHeightPx <= 0f) return bounds

        val rawLatSpan = (bounds.northLat - bounds.southLat).coerceAtLeast(MIN_SPAN)
        val usableHeightPx = (viewportHeightPx - sheetHeightPx).coerceAtLeast(1f)
        val availablePx = (usableHeightPx - 2 * paddingPx).coerceAtLeast(1f)
        val dppTarget = rawLatSpan / availablePx

        val centerLat = bounds.northLat - dppTarget * (viewportHeightPx / 2 - paddingPx)
        val widenedSpan = dppTarget * (viewportHeightPx - 2 * paddingPx).coerceAtLeast(1f)
        val halfSpan = widenedSpan / 2

        return bounds.copy(southLat = centerLat - halfSpan, northLat = centerLat + halfSpan)
    }

    /** Mirrors [MapCamera]'s own degenerate-box floor (a near-zero raw span, which
     * [MapCamera.target] never actually emits — two points that close collapse to `.Center` first
     * — but this stays defensive regardless, same rationale as iOS's `minimumBoundsSpan`). */
    private const val MIN_SPAN = 0.01
}
