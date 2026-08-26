package com.findly.android.ui.map

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyMapMarkerBubble
import com.findly.android.ui.groups.GroupMapMemberUi

/**
 * The A2 stub [MapRenderer] — kept post-A12 as a lightweight fallback for Compose previews/tests
 * that don't want a real `GoogleMap` view (see [MapRenderer]'s doc; [GoogleMapRenderer] is the
 * real implementation wired at [com.findly.android.AppContainer]'s composition root). Renders a
 * placeholder surface plus every device with a known location as a [FindlyMapMarkerBubble] — no
 * real geographic projection, but the roster's marker set is visible end-to-end so previews
 * compose without needing the Maps SDK. Stateless; composes only `ui/designsystem` components and
 * reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3) — no raw Material3 primitive
 * appears in this file. Tapping a bubble or the background surface still calls through to
 * [onMemberSelected]/[onBackgroundTap] (specs/010-app-shell-and-screen-ux.md §3.5) even though
 * there is no real camera to animate — [cameraCommand] is accepted for interface parity but
 * unused, since there is nothing here to point a camera at.
 */
class PlaceholderMapRenderer : MapRenderer {
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
            member.devices.filter { it.hasLocation }.map { device -> member to device }
        }

        Column(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(FindlyTheme.corner.lg))
                .background(FindlyTheme.colors.surfaceVariant)
                .clickable(onClick = onBackgroundTap)
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
        ) {
            if (markers.isEmpty()) {
                FindlyEmptyState(
                    title = "Map preview",
                    message = "Real tiles land with H1 (docs/azure-setup.md).",
                )
            } else {
                markers.forEach { (member, device) ->
                    FindlyMapMarkerBubble(
                        label = "${member.displayName} · ${device.deviceName}",
                        state = device.markerState,
                        selected = member.userId == selectedUserId,
                        modifier = Modifier.clickable { onMemberSelected(member.userId) },
                    )
                }
            }
        }
    }

    /** A5 addition (specs/005-temporary-groups.md §3) — same placeholder-surface treatment as
     * [Render], but position-only: no device name to compose into the label, just the member's
     * display name. */
    @Composable
    override fun RenderGroup(
        members: List<GroupMapMemberUi>,
        selectedUserId: String?,
        cameraCommand: CameraCommand?,
        onMemberSelected: (userId: String) -> Unit,
        onBackgroundTap: () -> Unit,
        modifier: Modifier,
    ) {
        val located = members.filter { it.hasLocation }

        Column(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(FindlyTheme.corner.lg))
                .background(FindlyTheme.colors.surfaceVariant)
                .clickable(onClick = onBackgroundTap)
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
        ) {
            if (located.isEmpty()) {
                FindlyEmptyState(
                    title = "Map preview",
                    message = "Real tiles land with H1 (docs/azure-setup.md).",
                )
            } else {
                located.forEach { member ->
                    FindlyMapMarkerBubble(
                        label = member.displayName,
                        state = member.markerState,
                        selected = member.userId == selectedUserId,
                        modifier = Modifier.clickable { onMemberSelected(member.userId) },
                    )
                }
            }
        }
    }
}
