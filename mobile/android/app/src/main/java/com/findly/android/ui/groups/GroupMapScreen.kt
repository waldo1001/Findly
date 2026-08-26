package com.findly.android.ui.groups

import android.widget.Toast
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
import androidx.compose.ui.platform.LocalContext
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
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.rememberFindlyBottomSheetState
import com.findly.android.ui.map.MapRenderer
import com.findly.android.ui.map.RelativeTimeFormatter
import com.findly.android.ui.map.RosterAvatarStack
import kotlinx.coroutines.delay
import java.time.Instant

private const val RELATIVE_TIME_TICKER_MS = 30_000L
private val FIT_ALL_BUTTON_BOTTOM_PADDING = 210.dp

/**
 * The A5 group-map screen (001-api-contract.md §12.10, specs/003-android-client.md §12.2).
 * **Position-only** (specs/005-temporary-groups.md §3): no device chips, no battery — the
 * [GroupMapMemberUi] roster simply has no such fields. specs/010-app-shell-and-screen-ux.md §3.2:
 * "adopts the same full-bleed + sheet layout and the same camera policy through the same renderer
 * seam" as the family map — this screen shares [MapRenderer] and [com.findly.android.ui.map.MapCameraPolicy]/
 * [com.findly.android.ui.map.RelativeTimeFormatter] with [com.findly.android.ui.map.MapScreen], and this task
 * (A34) fixes the identical zero-height-roster layout bug + camera-yank-on-refresh bug here too
 * (§3.2: "shipping the layout bug is not acceptable").
 *
 * On `GROUP_EXPIRED` ([GroupMapUiState.Expired]) the screen shows a brief [Toast] and bounces back
 * to the groups list via [onExpired] (specs/003 §12.2: "SHOULD bounce the user back to the groups
 * list with a 'this group has ended' notice") — a plain Android `Toast` rather than a new
 * design-system snackbar component, since no such component exists yet and a `Toast` needs none
 * of `FindlyTheme`'s styling (it's an OS-level surface, not part of this app's UI).
 */
@Composable
fun GroupMapRoute(
    viewModel: GroupMapViewModel,
    mapRenderer: MapRenderer,
    modifier: Modifier = Modifier,
    onExpired: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(state) {
        val expired = state as? GroupMapUiState.Expired ?: return@LaunchedEffect
        Toast.makeText(context, expired.message, Toast.LENGTH_SHORT).show()
        onExpired()
    }

    GroupMapScreen(
        state = state,
        mapRenderer = mapRenderer,
        onRefresh = viewModel::refresh,
        onSelectMember = viewModel::selectMember,
        onBackgroundTap = viewModel::deselect,
        onFitAll = viewModel::fitAll,
        modifier = modifier,
    )
}

@Composable
fun GroupMapScreen(
    state: GroupMapUiState,
    mapRenderer: MapRenderer,
    modifier: Modifier = Modifier,
    onRefresh: () -> Unit = {},
    onSelectMember: (userId: String) -> Unit = {},
    onBackgroundTap: () -> Unit = {},
    onFitAll: () -> Unit = {},
) {
    var nowIso by remember { mutableStateOf(Instant.now().toString()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(RELATIVE_TIME_TICKER_MS)
            nowIso = Instant.now().toString()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        when (state) {
            is GroupMapUiState.Loading -> FindlyLoadingState(message = "Loading group locations…")

            is GroupMapUiState.Error -> FindlyErrorState(
                title = "Couldn't load the map",
                message = state.message,
                onRetry = onRefresh,
            )

            // Transient — GroupMapRoute's LaunchedEffect is about to navigate away.
            is GroupMapUiState.Expired -> FindlyLoadingState(message = state.message)

            is GroupMapUiState.Content -> {
                if (state.members.isEmpty()) {
                    FindlyEmptyState(title = "No members yet", message = "Share the join code to get this group moving.")
                } else {
                    mapRenderer.RenderGroup(
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
                        header = { GroupRosterHeader(state = state) },
                    ) {
                        GroupRosterList(
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

        TopChrome(onRefresh = onRefresh)
    }
}

@Composable
private fun BoxScope.TopChrome(onRefresh: () -> Unit) {
    Row(
        modifier = Modifier
            .align(Alignment.TopCenter)
            .fillMaxWidth()
            .padding(FindlyTheme.spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        Box(modifier = Modifier.weight(1f))
        FindlyButton(text = "Refresh", onClick = onRefresh, style = FindlyButtonStyle.Secondary)
    }
}

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
private fun GroupRosterHeader(state: GroupMapUiState.Content) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = FindlyTheme.spacing.md),
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
    ) {
        Text(text = "Group", color = FindlyTheme.colors.onSurface, style = FindlyTheme.typography.titleMedium)
        Text(
            text = "${state.members.size} member${if (state.members.size == 1) "" else "s"}",
            color = FindlyTheme.colors.subtleText,
            style = FindlyTheme.typography.bodyMedium,
        )

        // specs/010 §3.1/§3.2 (normative — the family map's minimized-detent avatar stack
        // applies here too, "same components, same fix"; position-only initials from
        // displayName is no violation of 005 §3, no device/battery data involved).
        RosterAvatarStack(displayNames = state.members.map { it.displayName })
    }
}

@Composable
private fun GroupRosterList(
    members: List<GroupMapMemberUi>,
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
        items(members, key = { it.userId }) { member ->
            FindlyListRow(
                title = "${member.displayName} (${member.role})",
                subtitle = if (member.hasLocation) {
                    RelativeTimeFormatter.format(recordedAtIso = member.recordedAt!!, nowIso = nowIso)
                } else {
                    "No location yet"
                },
                selected = member.userId == selectedUserId,
                onClick = { onSelectMember(member.userId) },
                trailing = {
                    val (label, tone) = groupMemberStatus(member)
                    FindlyStatusChip(label = label, tone = tone, showStatusGlyph = true)
                },
            )
        }
    }
}

private fun groupMemberStatus(member: GroupMapMemberUi): Pair<String, FindlyStatusTone> = when {
    !member.hasLocation -> "No location" to FindlyStatusTone.Neutral
    member.isStale == true -> "Stale" to FindlyStatusTone.Warning
    else -> "Live" to FindlyStatusTone.Success
}

@Preview(name = "Group map — light", showBackground = true)
@Composable
private fun GroupMapScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        GroupMapScreen(
            state = GroupMapUiState.Content(
                members = listOf(
                    GroupMapMemberUi(
                        userId = "u1",
                        displayName = "Eric",
                        role = "owner",
                        lat = 51.0543,
                        lon = 3.7174,
                        accuracyM = 15.0,
                        recordedAt = "2026-07-21T09:58:00Z",
                        isStale = false,
                    ),
                ),
            ),
            mapRenderer = com.findly.android.ui.map.PlaceholderMapRenderer(),
        )
    }
}

@Preview(name = "Group map — dark", showBackground = true)
@Composable
private fun GroupMapScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        GroupMapScreen(state = GroupMapUiState.Loading, mapRenderer = com.findly.android.ui.map.PlaceholderMapRenderer())
    }
}
