package com.findly.android.ui.family

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * The Family (members) screen (specs/010-app-shell-and-screen-ux.md §4.1), extracted from the
 * retired `ui/settings/SettingsScreen.kt` monolith — device controls live on their own
 * [com.findly.android.ui.devices.DevicesScreen] now.
 */
@Composable
fun FamilyMembersRoute(
    viewModel: FamilyMembersViewModel,
    modifier: Modifier = Modifier,
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(state) {
        val current = state
        if (current is FamilyMembersUiState.RouteToOnboarding) onRouteToOnboarding(current.variant)
    }

    FamilyMembersScreen(
        state = state,
        onPromote = { userId -> viewModel.updateMemberRole(userId, role = "parent") },
        onDemote = { userId -> viewModel.updateMemberRole(userId, role = "member") },
        onRemoveMember = viewModel::removeMember,
        onRetry = viewModel::reload,
        modifier = modifier,
    )
}

@Composable
fun FamilyMembersScreen(
    state: FamilyMembersUiState,
    modifier: Modifier = Modifier,
    onPromote: (userId: String) -> Unit = {},
    onDemote: (userId: String) -> Unit = {},
    onRemoveMember: (userId: String) -> Unit = {},
    onRetry: () -> Unit = {},
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Family")

        when (state) {
            is FamilyMembersUiState.Loading -> FindlyLoadingState(message = "Loading…")

            is FamilyMembersUiState.Error -> FindlyErrorState(
                title = "Couldn't load your family",
                message = state.message,
                onRetry = onRetry,
            )

            is FamilyMembersUiState.RouteToOnboarding -> FindlyLoadingState(message = "Loading…")

            is FamilyMembersUiState.Content -> {
                val isParent = state.myRole == "parent"

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(FindlyTheme.spacing.md),
                    verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
                ) {
                    if (state.mutationError != null) {
                        FindlyStatusChip(label = state.mutationError, tone = FindlyStatusTone.Danger)
                    }

                    state.members.forEach { member ->
                        FindlyListRow(
                            title = member.displayName,
                            subtitle = member.role,
                            trailing = {
                                if (isParent) {
                                    if (member.role == "parent") {
                                        FindlyButton(
                                            text = "Demote",
                                            onClick = { onDemote(member.userId) },
                                            enabled = !state.isMutating,
                                            style = FindlyButtonStyle.Secondary,
                                        )
                                    } else {
                                        FindlyButton(
                                            text = "Promote",
                                            onClick = { onPromote(member.userId) },
                                            enabled = !state.isMutating,
                                            style = FindlyButtonStyle.Secondary,
                                        )
                                    }
                                    FindlyButton(
                                        text = "Remove",
                                        onClick = { onRemoveMember(member.userId) },
                                        enabled = !state.isMutating,
                                        style = FindlyButtonStyle.Secondary,
                                    )
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

@Preview(name = "Family — light", showBackground = true)
@Composable
private fun FamilyMembersScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        FamilyMembersScreen(
            state = FamilyMembersUiState.Content(
                familyName = "Wauters",
                myRole = "parent",
                members = listOf(
                    MemberUi("u1", "parent", "Eric", "2026-07-01T00:00:00Z"),
                    MemberUi("u2", "member", "Noor", "2026-07-02T00:00:00Z"),
                ),
            ),
        )
    }
}

@Preview(name = "Family — dark", showBackground = true)
@Composable
private fun FamilyMembersScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        FamilyMembersScreen(state = FamilyMembersUiState.Loading)
    }
}
