package com.findly.android.ui.map

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyBottomSheet
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyNavDrawerMenuButton
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.rememberFindlyBottomSheetState
import com.findly.android.ui.onboarding.OnboardingVariant
import kotlinx.coroutines.delay
import java.time.Instant

/** specs/010-app-shell-and-screen-ux.md §3.1: roster subtitles recompute their humanized relative
 * time on a 30 s ticker, never per frame. */
private const val RELATIVE_TIME_TICKER_MS = 30_000L

/** Clears the minimized sheet (186dp) plus a little breathing room, so the floating fit-all
 * button never sits under the sheet at its smallest detent. */
private val FIT_ALL_BUTTON_BOTTOM_PADDING = 210.dp

/**
 * The A2 live-map screen (001-api-contract.md §5.2, specs/003-android-client.md §12's `Map`
 * destination) — as of specs/010-app-shell-and-screen-ux.md §1.2/§3.1, also the NavHost **root**.
 * A33 landed the root's ☰ drawer button and the §2.1 dead-end routing rule; this task (A34) fixes
 * the two real bugs the handoff called out: the roster `LazyColumn` used to sit in an unweighted
 * `Column` sibling of the map (zero-height since A12) and the camera used to re-run on every
 * refresh. Both are retired here — full-bleed map (never a `Column` sibling), a
 * [FindlyBottomSheet] roster, and a camera that only moves on first load / an explicit fit-all /
 * member selection (010 §3.4, enforced by [MapStateHolder] — this screen only ever *renders*
 * `state.cameraCommand`, never decides when a new one should exist).
 */
@Composable
fun MapRoute(
    viewModel: MapViewModel,
    mapRenderer: MapRenderer,
    modifier: Modifier = Modifier,
    familyName: String = "Findly",
    onOpenDrawer: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
    onLocateNow: (userId: String, displayName: String) -> Unit = { _, _ -> },
) {
    val state by viewModel.state.collectAsState()
    MapScreen(
        state = state,
        mapRenderer = mapRenderer,
        familyName = familyName,
        onRefresh = viewModel::refresh,
        onSelectMember = viewModel::selectMember,
        onBackgroundTap = viewModel::deselect,
        onFitAll = viewModel::fitAll,
        onOpenDrawer = onOpenDrawer,
        onRouteToOnboarding = onRouteToOnboarding,
        onLocateNow = onLocateNow,
        modifier = modifier,
    )
}

@Composable
fun MapScreen(
    state: MapUiState,
    mapRenderer: MapRenderer,
    modifier: Modifier = Modifier,
    familyName: String = "Findly",
    onRefresh: () -> Unit = {},
    onSelectMember: (userId: String) -> Unit = {},
    onBackgroundTap: () -> Unit = {},
    onFitAll: () -> Unit = {},
    onOpenDrawer: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
    onLocateNow: (userId: String, displayName: String) -> Unit = { _, _ -> },
) {
    // specs/010-app-shell-and-screen-ux.md §2.1: PROFILE_NOT_FOUND/FAMILY_NOT_FOUND on this load
    // routes to Onboarding rather than rendering a retryable error card.
    LaunchedEffect(state) {
        if (state is MapUiState.RouteToOnboarding) onRouteToOnboarding(state.variant)
    }

    // specs/010 §3.1: humanized relative times recomputed on a 30 s ticker, never per frame — one
    // shared `nowIso` drives every roster row's RelativeTimeFormatter call below.
    var nowIso by remember { mutableStateOf(Instant.now().toString()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(RELATIVE_TIME_TICKER_MS)
            nowIso = Instant.now().toString()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
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
                        selectedUserId = state.selectedUserId,
                        cameraCommand = state.cameraCommand,
                        onMemberSelected = onSelectMember,
                        onBackgroundTap = onBackgroundTap,
                        modifier = Modifier.fillMaxSize(),
                    )

                    val sheetState = rememberFindlyBottomSheetState()
                    FindlyBottomSheet(
                        state = sheetState,
                        header = {
                            RosterHeader(state = state, onLocateNow = onLocateNow)
                        },
                    ) {
                        RosterList(
                            members = state.members,
                            selectedUserId = state.selectedUserId,
                            nowIso = nowIso,
                            onSelectMember = onSelectMember,
                        )
                    }

                    FitAllButton(onClick = onFitAll)
                }
            }
        }

        TopChrome(
            memberCount = (state as? MapUiState.Content)?.members?.size ?: 0,
            familyName = familyName,
            onOpenDrawer = onOpenDrawer,
            onRefresh = onRefresh,
        )
    }
}

@Composable
private fun BoxScope.TopChrome(
    memberCount: Int,
    familyName: String,
    onOpenDrawer: () -> Unit,
    onRefresh: () -> Unit,
) {
    Row(
        modifier = Modifier
            .align(Alignment.TopCenter)
            .fillMaxWidth()
            .padding(FindlyTheme.spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        FindlyNavDrawerMenuButton(onClick = onOpenDrawer)

        Box(
            modifier = Modifier
                .weight(1f)
                .shadow(elevation = FindlyTheme.elevation.level2, shape = RoundedCornerShape(FindlyTheme.corner.pill))
                .clip(RoundedCornerShape(FindlyTheme.corner.pill))
                .background(FindlyTheme.colors.surface)
                .padding(horizontal = FindlyTheme.spacing.md, vertical = FindlyTheme.spacing.sm),
        ) {
            Text(
                text = "$familyName · $memberCount member${if (memberCount == 1) "" else "s"}",
                color = FindlyTheme.colors.onSurface,
            )
        }

        FindlyButton(text = "Refresh", onClick = onRefresh, style = FindlyButtonStyle.Secondary)
    }
}

/** specs/010 §3.4's explicit fit-all action: a small floating map button (⌖-class glyph) that
 * re-runs the camera policy over current points. */
@Composable
private fun BoxScope.FitAllButton(onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .align(Alignment.BottomEnd)
            .padding(bottom = FIT_ALL_BUTTON_BOTTOM_PADDING, end = FindlyTheme.spacing.md)
            .size(48.dp)
            .shadow(elevation = FindlyTheme.elevation.level2, shape = CircleShape)
            .clip(CircleShape)
            .background(FindlyTheme.colors.surface)
            .clickable(onClick = onClick),
    ) {
        Text(text = "⌖", color = FindlyTheme.colors.primary)
    }
}

@Composable
private fun RosterHeader(
    state: MapUiState.Content,
    onLocateNow: (userId: String, displayName: String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = FindlyTheme.spacing.md),
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
    ) {
        Text(text = "Family", color = FindlyTheme.colors.onSurface, style = FindlyTheme.typography.titleMedium)
        Text(
            text = "${state.members.size} member${if (state.members.size == 1) "" else "s"}",
            color = FindlyTheme.colors.subtleText,
            style = FindlyTheme.typography.bodyMedium,
        )

        // specs/010 §3.1/§3.5: "Locate now" surfaces in the sheet's minimized/standard header
        // exactly when a member is selected.
        val selected = state.members.firstOrNull { it.userId == state.selectedUserId }
        if (selected != null) {
            FindlyButton(
                text = "Locate now",
                onClick = { onLocateNow(selected.userId, selected.displayName) },
                style = FindlyButtonStyle.Primary,
            )
        }
    }
}

@Composable
private fun RosterList(
    members: List<RosterMemberUi>,
    selectedUserId: String?,
    nowIso: String,
    onSelectMember: (userId: String) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = FindlyTheme.spacing.md),
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
    ) {
        members.forEach { member ->
            if (member.devices.isEmpty()) {
                item(key = member.userId) {
                    FindlyListRow(
                        title = member.displayName,
                        subtitle = "No devices registered",
                        selected = member.userId == selectedUserId,
                        // specs/010 §3.5: tapping a roster row selects (and, behind that
                        // selection, surfaces "Locate now") — replaces the old direct
                        // navigate-to-Locate row tap.
                        onClick = { onSelectMember(member.userId) },
                    )
                }
            } else {
                items(member.devices, key = { it.deviceId }) { device ->
                    FindlyListRow(
                        title = "${member.displayName} · ${device.deviceName}",
                        // specs/010 §3.1: humanized relative time, recomputed on the 30 s
                        // [nowIso] ticker — never the raw ISO string, never per-frame.
                        subtitle = if (device.hasLocation) {
                            RelativeTimeFormatter.format(recordedAtIso = device.recordedAt!!, nowIso = nowIso)
                        } else {
                            "No location yet"
                        },
                        selected = member.userId == selectedUserId,
                        onClick = { onSelectMember(member.userId) },
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
