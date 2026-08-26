package com.findly.android.ui.groups

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant
import java.time.Instant

/**
 * The A5 groups list screen (001-api-contract.md §12.2, specs/003-android-client.md §12.2):
 * every group the caller belongs to, plus entry points to create/join one. Doubles as the
 * **family-less home** (`Content.hasFamily == false`) — a signed-in user with no family (§1.5.4)
 * is no longer a dead end here, unlike every family-scoped A2 screen; [onManageFamily] routes to
 * the existing `Invites` screen (§3.4's join-a-family flow). The former **A21 profile-less
 * first-run home** (`GroupsListUiState.ProfileNeeded`) is retired by specs/010-app-shell-and-
 * screen-ux.md §2.1/§6: a signed-in user with no `Users` profile row at all now gets
 * [GroupsListUiState.RouteToOnboarding] here instead, routing to the new Onboarding screen (010
 * §2.2), which offers the four bootstrap paths this screen used to render inline.
 *
 * The `LaunchedEffect(Unit) { viewModel.refresh() }` re-fetches every time this composable
 * re-enters composition (returning from `GroupCreate`/`GroupJoin`/`GroupDetail`/`GroupMap`, all of
 * which pop back to this destination) — the "list re-load then reflects the true state"
 * specs/003 §12.2 requires after a create/join or a `GROUP_EXPIRED` bounce-back. The underlying
 * [GroupsListViewModel] (and its `GroupsListStateHolder`) survives across that pop, scoped to the
 * nav back-stack entry, so this is a genuine re-fetch, not a fresh `StateHolder` re-`init`.
 */
@Composable
fun GroupsListRoute(
    viewModel: GroupsListViewModel,
    modifier: Modifier = Modifier,
    onCreateGroup: (GroupsListUiState.CreateJoinContext) -> Unit = {},
    onJoinGroup: (GroupsListUiState.CreateJoinContext) -> Unit = {},
    onOpenGroup: (groupId: String) -> Unit = {},
    onManageFamily: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(Unit) { viewModel.refresh() }
    GroupsListScreen(
        state = state,
        onRefresh = viewModel::refresh,
        onCreateGroup = onCreateGroup,
        onJoinGroup = onJoinGroup,
        onOpenGroup = onOpenGroup,
        onManageFamily = onManageFamily,
        onRouteToOnboarding = onRouteToOnboarding,
        modifier = modifier,
    )
}

@Composable
fun GroupsListScreen(
    state: GroupsListUiState,
    modifier: Modifier = Modifier,
    onRefresh: () -> Unit = {},
    onCreateGroup: (GroupsListUiState.CreateJoinContext) -> Unit = {},
    onJoinGroup: (GroupsListUiState.CreateJoinContext) -> Unit = {},
    onOpenGroup: (groupId: String) -> Unit = {},
    onManageFamily: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule (the retired ProfileNeeded
    // first-run state's replacement — 010 §6).
    LaunchedEffect(state) {
        if (state is GroupsListUiState.RouteToOnboarding) onRouteToOnboarding(state.variant)
    }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(
            title = "Groups",
            actions = {
                FindlyButton(text = "Refresh", onClick = onRefresh, style = FindlyButtonStyle.Secondary)
            },
        )

        when (state) {
            is GroupsListUiState.Loading -> FindlyLoadingState(message = "Loading groups…")

            is GroupsListUiState.Error -> FindlyErrorState(
                title = "Couldn't load groups",
                message = state.message,
                onRetry = onRefresh,
            )

            is GroupsListUiState.RouteToOnboarding -> FindlyLoadingState(message = "Loading groups…")

            is GroupsListUiState.Content -> {
                val createJoinContext = GroupsListUiState.CreateJoinContext(limits = state.limits, needsDisplayName = false)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(FindlyTheme.spacing.md),
                    verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
                ) {
                    if (!state.hasFamily) {
                        FindlyCard {
                            Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                                FindlyStatusChip(label = "No family yet", tone = FindlyStatusTone.Neutral)
                                FindlyButton(
                                    text = "Manage family invites",
                                    onClick = onManageFamily,
                                    style = FindlyButtonStyle.Secondary,
                                )
                            }
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                        FindlyButton(text = "Create group", onClick = { onCreateGroup(createJoinContext) })
                        FindlyButton(text = "Join group", onClick = { onJoinGroup(createJoinContext) }, style = FindlyButtonStyle.Secondary)
                    }
                }

                if (state.groups.isEmpty()) {
                    FindlyEmptyState(
                        title = "No groups yet",
                        message = "Create a group or join one with a code to get started.",
                    )
                } else {
                    val now = Instant.now().toString()
                    LazyColumn(
                        modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md),
                        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
                    ) {
                        items(state.groups, key = { it.groupId }) { group ->
                            FindlyCard(modifier = Modifier.fillMaxWidth()) {
                                Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                                        val (label, tone) = groupStateStatus(group.state)
                                        FindlyStatusChip(label = label, tone = tone)
                                        FindlyStatusChip(
                                            label = GroupCountdownFormatter.format(group.endsAt, now),
                                            tone = FindlyStatusTone.Neutral,
                                        )
                                    }
                                    FindlyButton(
                                        text = "${group.name} · ${group.memberCount} member${if (group.memberCount == 1) "" else "s"}",
                                        onClick = { onOpenGroup(group.groupId) },
                                        style = FindlyButtonStyle.Secondary,
                                        modifier = Modifier.fillMaxWidth(),
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

private fun groupStateStatus(state: String): Pair<String, FindlyStatusTone> = when (state) {
    "active" -> "Active" to FindlyStatusTone.Success
    "ended" -> "Ended (grace)" to FindlyStatusTone.Warning
    "archived" -> "Archived" to FindlyStatusTone.Neutral
    else -> state to FindlyStatusTone.Neutral
}

@Preview(name = "Groups — light", showBackground = true)
@Composable
private fun GroupsListScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        GroupsListScreen(
            state = GroupsListUiState.Content(
                groups = listOf(
                    GroupSummaryUi(
                        groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz",
                        name = "Festival crew",
                        endsAt = "2026-08-02T22:00:00Z",
                        expiryPolicy = "delete",
                        state = "active",
                        role = "owner",
                        memberCount = 7,
                        code = "7F3K9QRZ",
                    ),
                ),
                limits = null,
                hasFamily = true,
            ),
        )
    }
}

@Preview(name = "Groups — dark (family-less, empty)", showBackground = true)
@Composable
private fun GroupsListScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        GroupsListScreen(
            state = GroupsListUiState.Content(
                groups = emptyList(),
                limits = null,
                hasFamily = false,
            ),
        )
    }
}

@Preview(name = "Groups — loading (transient, routing to Onboarding)", showBackground = true)
@Composable
private fun GroupsListScreenRouteToOnboardingPreview() {
    FindlyTheme(darkTheme = false) {
        GroupsListScreen(state = GroupsListUiState.RouteToOnboarding(OnboardingVariant.ProfileLess))
    }
}
