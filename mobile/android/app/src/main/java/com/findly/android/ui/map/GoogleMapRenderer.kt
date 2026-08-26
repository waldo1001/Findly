package com.findly.android.ui.map

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
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
 * existing `FindlyBottomSheet` roster), the same split already shipped on iOS
 * (`LiveMapViewModel.annotations` excludes no-fix devices from the map layer but the roster still
 * lists them — specs/004-ios-client.md), so both apps render identically per §5.2.
 *
 * Camera fit is decided by the pure, unit-tested [MapCamera]/[MapCameraPolicy]
 * (`MapCameraTest`/`MapCameraPolicyTest`/`MapStateHolderTest`) — only the actual
 * `CameraUpdateFactory`/`LatLngBounds` translation happens here, since that needs a real
 * `GoogleMap` view. specs/010-app-shell-and-screen-ux.md §3.4 (normative): [MapSurface] keys its
 * camera-animation [LaunchedEffect] on `cameraCommand?.seq` alone — **never** on the marker/points
 * list — which is what stops an ordinary refresh (markers changing) from moving the camera; only
 * a genuinely new [CameraCommand] (a new `seq`, minted by the state holder on first load, an
 * explicit fit-all, or a selection) re-runs it.
 */
class GoogleMapRenderer : MapRenderer {

    @Composable
    override fun Render(
        members: List<RosterMemberUi>,
        selectedUserId: String?,
        cameraCommand: CameraCommand?,
        onMemberSelected: (userId: String) -> Unit,
        onBackgroundTap: () -> Unit,
        modifier: Modifier,
    ) {
        val markers = members.flatMap { member ->
            member.devices.filter { it.hasLocation }.map { device ->
                MapMarker(
                    id = device.deviceId,
                    userId = member.userId,
                    lat = device.lat!!,
                    lon = device.lon!!,
                    label = initialsFor(member.displayName),
                    state = device.markerState,
                )
            }
        }
        MapSurface(
            markers = markers,
            selectedUserId = selectedUserId,
            cameraCommand = cameraCommand,
            onMemberSelected = onMemberSelected,
            onBackgroundTap = onBackgroundTap,
            modifier = modifier,
        )
    }

    /** A5/A12 (specs/005-temporary-groups.md §3): position-only — same visual language as
     * [Render], no device/battery detail in the marker content. */
    @Composable
    override fun RenderGroup(
        members: List<GroupMapMemberUi>,
        selectedUserId: String?,
        cameraCommand: CameraCommand?,
        onMemberSelected: (userId: String) -> Unit,
        onBackgroundTap: () -> Unit,
        modifier: Modifier,
    ) {
        val markers = members.filter { it.hasLocation }.map { member ->
            MapMarker(
                id = member.userId,
                userId = member.userId,
                lat = member.lat!!,
                lon = member.lon!!,
                label = initialsFor(member.displayName),
                state = member.markerState,
            )
        }
        MapSurface(
            markers = markers,
            selectedUserId = selectedUserId,
            cameraCommand = cameraCommand,
            onMemberSelected = onMemberSelected,
            onBackgroundTap = onBackgroundTap,
            modifier = modifier,
        )
    }
}

/** One plotted pin — already resolved to a known coordinate; callers filter out
 * `hasLocation == false` entries first, since there is nowhere on the map to plot those. [id] is
 * the Compose `key()` (per-device on the family map, so two devices at the same spot don't
 * collide); [userId] is the member selection targets — several device markers can share one
 * [userId] on the family map. */
private data class MapMarker(
    val id: String,
    val userId: String,
    val lat: Double,
    val lon: Double,
    val label: String,
    val state: FindlyMapMarkerState,
)

@Composable
private fun MapSurface(
    markers: List<MapMarker>,
    selectedUserId: String?,
    cameraCommand: CameraCommand?,
    onMemberSelected: (userId: String) -> Unit,
    onBackgroundTap: () -> Unit,
    modifier: Modifier,
) {
    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(
            LatLng(MapCamera.DEFAULT_LAT, MapCamera.DEFAULT_LON),
            MapCamera.DEFAULT_ZOOM,
        )
    }
    val density = LocalDensity.current

    // specs/010-app-shell-and-screen-ux.md §3.4: keyed on the command's `seq` alone — NOT on
    // `markers`/`points` — so a refresh that only changes marker positions (no new seq) never
    // re-triggers this effect. This is the actual fix for "every marker-set change yanks the
    // camera"; MapStateHolder/GroupMapStateHolder decide WHEN a new seq is minted.
    LaunchedEffect(cameraCommand?.seq) {
        val target = cameraCommand?.target ?: return@LaunchedEffect
        val update = when (target) {
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
                with(density) { target.paddingDp.dp.roundToPx() },
            )
        }
        // Suspends until a map is actually bound (maps-compose's CameraPositionState.animate
        // contract).
        cameraPositionState.animate(update)
    }

    GoogleMap(
        modifier = modifier.fillMaxSize(),
        cameraPositionState = cameraPositionState,
        onMapClick = { onBackgroundTap() },
    ) {
        markers.forEach { marker ->
            key(marker.id) {
                val selected = marker.userId == selectedUserId
                MarkerComposable(
                    marker.label,
                    marker.state,
                    selected,
                    state = rememberUpdatedMarkerState(position = LatLng(marker.lat, marker.lon)),
                    title = marker.label,
                    onClick = {
                        onMemberSelected(marker.userId)
                        true
                    },
                ) {
                    FindlyMapMarkerBubble(label = marker.label, state = marker.state, selected = selected)
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
