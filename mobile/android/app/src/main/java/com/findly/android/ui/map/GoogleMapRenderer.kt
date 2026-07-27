package com.findly.android.ui.map

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import com.findly.android.ui.designsystem.components.FindlyMapMarkerBubble
import com.findly.android.ui.designsystem.components.FindlyMapMarkerState
import com.findly.android.ui.groups.GroupMapMemberUi
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MarkerComposable
import com.google.maps.android.compose.rememberCameraPositionState
import com.google.maps.android.compose.rememberUpdatedMarkerState

/**
 * A12 (specs/003-android-client.md §12; docs/store-release-roadmap.md) — the real Google Maps
 * Compose [MapRenderer] implementation, replacing [PlaceholderMapRenderer] at
 * [com.findly.android.AppContainer]'s composition root. It never reads
 * `AppConfig.mapsApiKey` itself: the Maps SDK reads the key once, at process start, from the
 * manifest's `com.google.android.geo.API_KEY` meta-data (app/build.gradle.kts's
 * `manifestPlaceholders["mapsApiKey"]` / AndroidManifest.xml). An empty key (the default until
 * H1 provisions a real one, docs/azure-setup.md) still builds and runs fine — the map simply
 * renders a tile-less grey surface, the same "degrade gracefully without secrets" pattern every
 * other H1-waived dependency in this codebase already uses; this class needs no key-presence
 * branch at all.
 *
 * Markers are rendered as the design-system [FindlyMapMarkerBubble] via `maps-compose`'s
 * `MarkerComposable` (arbitrary Compose content as a marker icon), never a default red pin, so
 * the real map and [PlaceholderMapRenderer] always show the identical three
 * [FindlyMapMarkerState] states (design/findly-design-system/README.md's `MapMarkerBubble` spec:
 * online = solid `success` fill + tail; stale = desaturated + dashed ring; no-location-yet =
 * neutral "?" chip). A device/member with no fix yet carries **no coordinate to plot**
 * (001-api-contract.md §5.2/§12.10 — `lat`/`lon` are `null`), so it is never placed on the map
 * surface at all — inventing a default location would violate the spec's "never falsely placed"
 * rule. It still surfaces in the roster list beneath the map ([MapScreen]/[GroupMapScreen]'s
 * existing `LazyColumn`), the same split already shipped on iOS
 * (`LiveMapViewModel.annotations` excludes no-fix devices from the map layer but the roster still
 * lists them — specs/004-ios-client.md), so both apps render identically per §5.2.
 *
 * Camera fit is decided by the pure, unit-tested [MapCamera] (`MapCameraTest`) — only the actual
 * `CameraUpdateFactory`/`LatLngBounds` translation happens here, since that needs a real
 * `GoogleMap` view.
 */
class GoogleMapRenderer : MapRenderer {

    @Composable
    override fun Render(members: List<RosterMemberUi>, modifier: Modifier) {
        val markers = members.flatMap { member ->
            member.devices.filter { it.hasLocation }.map { device ->
                MapMarker(
                    id = device.deviceId,
                    lat = device.lat!!,
                    lon = device.lon!!,
                    label = initialsFor(member.displayName),
                    state = device.markerState,
                )
            }
        }
        MapSurface(markers = markers, modifier = modifier)
    }

    /** A5/A12 (specs/005-temporary-groups.md §3): position-only — same visual language as
     * [Render], no device/battery detail in the marker content. */
    @Composable
    override fun RenderGroup(members: List<GroupMapMemberUi>, modifier: Modifier) {
        val markers = members.filter { it.hasLocation }.map { member ->
            MapMarker(
                id = member.userId,
                lat = member.lat!!,
                lon = member.lon!!,
                label = initialsFor(member.displayName),
                state = member.markerState,
            )
        }
        MapSurface(markers = markers, modifier = modifier)
    }
}

/** One plotted pin — already resolved to a known coordinate; callers filter out
 * `hasLocation == false` entries first, since there is nowhere on the map to plot those. */
private data class MapMarker(
    val id: String,
    val lat: Double,
    val lon: Double,
    val label: String,
    val state: FindlyMapMarkerState,
)

@Composable
private fun MapSurface(markers: List<MapMarker>, modifier: Modifier) {
    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(
            LatLng(MapCamera.DEFAULT_LAT, MapCamera.DEFAULT_LON),
            MapCamera.DEFAULT_ZOOM,
        )
    }

    val points = markers.map { it.lat to it.lon }
    LaunchedEffect(points) {
        val update = when (val target = MapCamera.target(points)) {
            is MapCameraTarget.Default -> CameraUpdateFactory.newLatLngZoom(
                LatLng(target.lat, target.lon),
                target.zoom,
            )
            is MapCameraTarget.Center -> CameraUpdateFactory.newLatLngZoom(
                LatLng(target.lat, target.lon),
                target.zoom,
            )
            is MapCameraTarget.Bounds -> CameraUpdateFactory.newLatLngBounds(
                LatLngBounds(
                    LatLng(target.southLat, target.westLon),
                    LatLng(target.northLat, target.eastLon),
                ),
                target.paddingPx,
            )
        }
        // Suspends until a map is actually bound (maps-compose's CameraPositionState.animate
        // contract) — safe to call eagerly on every composition/marker-set change.
        cameraPositionState.animate(update)
    }

    GoogleMap(modifier = modifier.fillMaxSize(), cameraPositionState = cameraPositionState) {
        markers.forEach { marker ->
            key(marker.id) {
                MarkerComposable(
                    marker.label,
                    marker.state,
                    state = rememberUpdatedMarkerState(position = LatLng(marker.lat, marker.lon)),
                    title = marker.label,
                ) {
                    FindlyMapMarkerBubble(label = marker.label, state = marker.state)
                }
            }
        }
    }
}

/** Same short-label convention as iOS's `LiveMapViewModel.initials(for:)`
 * (specs/004-ios-client.md) — a real map pin has no room for a full "name · device" label, unlike
 * [PlaceholderMapRenderer]'s roster-style rendering. */
private fun initialsFor(displayName: String): String {
    val trimmed = displayName.trim()
    if (trimmed.isEmpty()) return "?"
    return trimmed.take(2).uppercase()
}
