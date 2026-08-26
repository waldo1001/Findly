package com.findly.android.ui.groups

import com.findly.android.ui.map.CameraCommand

/** One group member's live-map entry (001-api-contract.md §12.10). **Position-only** (specs/005-
 * temporary-groups.md §3): deliberately no `deviceId`/`deviceName`/`batteryPct`/`source`/altitude/
 * speed/bearing anywhere in this type — unlike [com.findly.android.ui.map.RosterDeviceUi],
 * there simply are no such fields to carry, mirroring the DTO this maps from
 * ([com.findly.android.network.dto.GroupMemberLocationDto]). */
data class GroupMapMemberUi(
    val userId: String,
    val displayName: String,
    val role: String,
    val lat: Double?,
    val lon: Double?,
    val accuracyM: Double?,
    val recordedAt: String?,
    val isStale: Boolean?,
) {
    val hasLocation: Boolean get() = lat != null && lon != null
}

/** State surfaced by [GroupMapStateHolder] (specs/003-android-client.md §12.2's
 * `GroupMapScreen`). */
sealed class GroupMapUiState {
    data object Loading : GroupMapUiState()
    data class Error(val message: String) : GroupMapUiState()

    /** `GROUP_EXPIRED` (001 §12.10 — only `active` groups serve this endpoint) — bounce back to
     * the groups list with a notice, same treatment as [GroupDetailUiState.Expired]. */
    data class Expired(val message: String = "This group has ended.") : GroupMapUiState()

    /** [selectedUserId]/[cameraCommand] mirror [com.findly.android.ui.map.MapUiState.Content]'s
     * fields exactly (specs/010-app-shell-and-screen-ux.md §3.2's "same camera policy through the
     * same renderer seam") — position-only, so selection targets the member's own single point
     * directly rather than resolving a freshest device first. */
    data class Content(
        val members: List<GroupMapMemberUi>,
        val isRefreshing: Boolean = false,
        val selectedUserId: String? = null,
        val cameraCommand: CameraCommand? = null,
    ) : GroupMapUiState()
}
