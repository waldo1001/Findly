package com.findly.android.ui.map

import com.findly.android.ui.designsystem.components.FindlyMapMarkerState
import com.findly.android.ui.groups.GroupMapMemberUi

/**
 * A12 (specs/003-android-client.md §12) — pure derivation of a [FindlyMapMarkerState] from what
 * the server already computed (001-api-contract.md §5.2's `isStale` formula, `now − recordedAt >
 * 2 × syncIntervalMinutes`) — the client MUST NOT recompute staleness itself, only render one of
 * the three design-system states (design/findly-design-system/README.md's `MapMarkerBubble`
 * spec): no fix yet → [FindlyMapMarkerState.NoLocation]; `isStale == true` →
 * [FindlyMapMarkerState.Stale]; otherwise → [FindlyMapMarkerState.Online]. `isStale == null`
 * alongside a known location should never happen server-side (§5.2: `isStale` is only null when
 * `lat`/`lon` are also null), but defaults to `Online` rather than crashing, matching the existing
 * `device.isStale ?: false` convention already used by [PlaceholderMapRenderer].
 */
fun markerStateFor(hasLocation: Boolean, isStale: Boolean?): FindlyMapMarkerState = when {
    !hasLocation -> FindlyMapMarkerState.NoLocation
    isStale == true -> FindlyMapMarkerState.Stale
    else -> FindlyMapMarkerState.Online
}

/** The family map's per-device marker state (§5.2). */
val RosterDeviceUi.markerState: FindlyMapMarkerState
    get() = markerStateFor(hasLocation, isStale)

/** The group map's per-member marker state (§12.10) — position-only, same visual language as
 * [RosterDeviceUi.markerState] (specs/003-android-client.md §12.2). */
val GroupMapMemberUi.markerState: FindlyMapMarkerState
    get() = markerStateFor(hasLocation, isStale)
