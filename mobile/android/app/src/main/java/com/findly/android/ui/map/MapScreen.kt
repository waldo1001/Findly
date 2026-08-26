package com.findly.android.ui.map

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyNavDrawerMenuButton
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * The A2 live-map screen (001-api-contract.md §5.2, specs/003-android-client.md §12's `Map`
 * destination) — as of specs/010-app-shell-and-screen-ux.md §1.2/§3.1, also the NavHost **root**:
 * this task (A33) only adds the root's ☰ drawer button ([onOpenDrawer]) and the §2.1 dead-end
 * routing rule; the full-bleed layout, bottom-sheet roster, and camera policy (010 §3) are A34's
 * revamp and land in a later task — [FindlyTopBar]'s trailing "Refresh" action and the plain
 * `LazyColumn` roster below the map are therefore unchanged here on purpose. Rendered entirely
 * through `ui/designsystem` components plus the swappable [MapRenderer], driven by state hoisted
 * from [MapViewModel]/[MapStateHolder]. No styling constant appears in this file.
 */
@Composable
fun MapRoute(
    viewModel: MapViewModel,
    mapRenderer: MapRenderer,
    modifier: Modifier = Modifier,
    onSelectMember: (userId: String, displayName: String) -> Unit = { _, _ -> },
    onOpenDrawer: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    MapScreen(
        state = state,
        mapRenderer = mapRenderer,
        onRefresh = viewModel::refresh,
        onSelectMember = onSelectMember,
        onOpenDrawer = onOpenDrawer,
        onRouteToOnboarding = onRouteToOnboarding,
        modifier = modifier,
    )
}

@Composable
fun MapScreen(
    state: MapUiState,
    mapRenderer: MapRenderer,
    modifier: Modifier = Modifier,
    onRefresh: () -> Unit = {},
    onSelectMember: (userId: String, displayName: String) -> Unit = { _, _ -> },
    onOpenDrawer: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    // specs/010-app-shell-and-screen-ux.md §2.1: PROFILE_NOT_FOUND/FAMILY_NOT_FOUND on this load
    // routes to Onboarding rather than rendering a retryable error card — this effect is the one
    // place that reacts to it, mirroring every other LaunchedEffect-driven navigation in this
    // module (e.g. FindlyNavHost's own authState effect).
    LaunchedEffect(state) {
        if (state is MapUiState.RouteToOnboarding) onRouteToOnboarding(state.variant)
    }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(
            title = "Family map",
            navigationIcon = { FindlyNavDrawerMenuButton(onClick = onOpenDrawer) },
            actions = {
                FindlyButton(text = "Refresh", onClick = onRefresh, style = FindlyButtonStyle.Secondary)
            },
        )

        when (state) {
            is MapUiState.Loading -> FindlyLoadingState(message = "Loading family locations…")

            is MapUiState.Error -> FindlyErrorState(
                title = "Couldn't load the map",
                message = state.message,
                onRetry = onRefresh,
            )

            is MapUiState.RouteToOnboarding -> FindlyLoadingState(message = "Loading family locations…")

            is MapUiState.Content -> {
                if (state.members.isEmpty()) {
                    FindlyEmptyState(title = "No family yet", message = "Join or create a family to see the map.")
                } else {
                    mapRenderer.Render(
                        members = state.members,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(FindlyTheme.spacing.md),
                    )

                    LazyColumn(
                        modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md),
                        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
                    ) {
                        state.members.forEach { member ->
                            if (member.devices.isEmpty()) {
                                item(key = member.userId) {
                                    FindlyListRow(
                                        title = member.displayName,
                                        subtitle = "No devices registered",
                                        onClick = { onSelectMember(member.userId, member.displayName) },
                                    )
                                }
                            } else {
                                items(member.devices, key = { it.deviceId }) { device ->
                                    FindlyListRow(
                                        title = "${member.displayName} · ${device.deviceName}",
                                        subtitle = if (device.hasLocation) {
                                            "Updated ${device.recordedAt}"
                                        } else {
                                            "No location yet"
                                        },
                                        onClick = { onSelectMember(member.userId, member.displayName) },
                                        trailing = {
                                            val (label, tone) = deviceStatus(device)
                                            FindlyStatusChip(label = label, tone = tone, showStatusGlyph = true)
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun deviceStatus(device: RosterDeviceUi): Pair<String, FindlyStatusTone> = when {
    !device.trackingEnabled -> "Paused" to FindlyStatusTone.Neutral
    !device.hasLocation -> "No location" to FindlyStatusTone.Neutral
    device.isStale == true -> "Stale" to FindlyStatusTone.Warning
    else -> "Live" to FindlyStatusTone.Success
}

@Preview(name = "Map — light", showBackground = true)
@Composable
private fun MapScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        MapScreen(
            state = MapUiState.Content(
                members = listOf(
                    RosterMemberUi(
                        userId = "u1",
                        displayName = "Eric",
                        devices = listOf(
                            RosterDeviceUi(
                                deviceId = "d1",
                                deviceName = "Pixel 8",
                                lat = 51.0543,
                                lon = 3.7174,
                                recordedAt = "2026-07-19T09:05:12Z",
                                batteryPct = 78,
                                trackingEnabled = true,
                                syncIntervalMinutes = 15,
                                isStale = false,
                            ),
                        ),
                    ),
                ),
            ),
            mapRenderer = PlaceholderMapRenderer(),
        )
    }
}

@Preview(name = "Map — dark", showBackground = true)
@Composable
private fun MapScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        MapScreen(state = MapUiState.Loading, mapRenderer = PlaceholderMapRenderer())
    }
}
