package com.findly.android.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.nav.Destinations

/**
 * The A1 proof screen (specs/003-android-client.md §12): rendered entirely through
 * `ui/designsystem` components, driven by state hoisted from [HomeViewModel]/[HomeStateHolder].
 * No styling constant appears in this file — only [FindlyTheme]-derived component calls.
 *
 * A2 addition: once registered, a short quick-nav list of [FindlyButton]s reaches the feature
 * screens A1 only reserved route names for ([Destinations]) — this app has no bottom-nav/drawer
 * design-system component yet, so this is the minimal reachability wiring rather than a proper
 * navigation shell; a future design pass can replace it without touching any screen beneath it.
 */
@Composable
fun HomeRoute(
    viewModel: HomeViewModel,
    onSignIn: () -> Unit,
    modifier: Modifier = Modifier,
    onNavigate: (route: String) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    HomeScreen(state = state, onSignIn = onSignIn, onNavigate = onNavigate, modifier = modifier)
}

@Composable
fun HomeScreen(
    state: HomeUiState,
    modifier: Modifier = Modifier,
    onSignIn: () -> Unit = {},
    onNavigate: (route: String) -> Unit = {},
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Findly")

        Column(
            modifier = Modifier.padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            when (state) {
                is HomeUiState.Loading -> FindlyLoadingState(message = "Loading…")

                is HomeUiState.SignedOut -> {
                    FindlyEmptyState(
                        title = "Not signed in",
                        message = "Sign in to see your family's locations.",
                    )
                    FindlyButton(text = "Sign in", onClick = onSignIn)
                }

                is HomeUiState.SignedIn -> {
                    val (label, tone) = when (state.registration) {
                        HomeUiState.RegistrationStatus.Registering ->
                            "Registering device…" to FindlyStatusTone.Neutral
                        HomeUiState.RegistrationStatus.Registered ->
                            "Device registered" to FindlyStatusTone.Success
                        HomeUiState.RegistrationStatus.Failed ->
                            "Registration failed" to FindlyStatusTone.Danger
                    }
                    FindlyStatusChip(label = label, tone = tone)
                    if (state.registration == HomeUiState.RegistrationStatus.Failed) {
                        FindlyErrorState(
                            title = "Couldn't register this device",
                            message = "Check your connection and try again.",
                        )
                    }
                    if (state.registration != HomeUiState.RegistrationStatus.Registering) {
                        FindlyButton(text = "Family map", onClick = { onNavigate(Destinations.Map.route) }, style = FindlyButtonStyle.Secondary)
                        FindlyButton(text = "History", onClick = { onNavigate(Destinations.History.route) }, style = FindlyButtonStyle.Secondary)
                        FindlyButton(text = "Geofences", onClick = { onNavigate(Destinations.Geofences.route) }, style = FindlyButtonStyle.Secondary)
                        FindlyButton(text = "Settings", onClick = { onNavigate(Destinations.Settings.route) }, style = FindlyButtonStyle.Secondary)
                        FindlyButton(text = "Invites", onClick = { onNavigate(Destinations.Invites.route) }, style = FindlyButtonStyle.Secondary)
                        // A5 addition (specs/005-temporary-groups.md, specs/003 §12.2): works
                        // without a family (§1.5.4) — the one destination that's never a dead
                        // end for a family-less signed-in user, unlike every button above.
                        FindlyButton(text = "Groups", onClick = { onNavigate(Destinations.Groups.route) }, style = FindlyButtonStyle.Secondary)
                    }
                }
            }
        }
    }
}

@Preview(name = "Home — light", showBackground = true)
@Composable
private fun HomeScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        HomeScreen(state = HomeUiState.SignedIn("uid-preview", HomeUiState.RegistrationStatus.Registered))
    }
}

@Preview(name = "Home — dark", showBackground = true)
@Composable
private fun HomeScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        HomeScreen(state = HomeUiState.SignedOut)
    }
}
