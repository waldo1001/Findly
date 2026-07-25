package com.findly.android.ui.locate

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
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The A2 "locate now" screen (001-api-contract.md §6, specs/003-android-client.md §12's `Locate`
 * destination): a single action that creates a locate request, then polls
 * [LocateViewModel]/[LocateStateHolder] every 2 s until a terminal state
 * (`fulfilled`/`expired`/`pushFailed`) is reached, rendering `lastKnown` immediately as the
 * instant answer.
 */
@Composable
fun LocateRoute(
    viewModel: LocateViewModel,
    targetUserId: String,
    targetDisplayName: String,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    LocateScreen(
        state = state,
        targetDisplayName = targetDisplayName,
        onLocateNow = { viewModel.requestLocate(targetUserId = targetUserId) },
        modifier = modifier,
    )
}

@Composable
fun LocateScreen(
    state: LocateUiState,
    modifier: Modifier = Modifier,
    targetDisplayName: String = "",
    onLocateNow: () -> Unit = {},
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Locate $targetDisplayName")

        Column(
            modifier = Modifier.padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
        ) {
            when (state) {
                is LocateUiState.Idle -> {
                    FindlyEmptyState(title = "Locate $targetDisplayName", message = "Get their current location now.")
                    FindlyButton(text = "Locate now", onClick = onLocateNow)
                }

                is LocateUiState.Error -> FindlyErrorState(
                    title = "Couldn't request a location",
                    message = state.message,
                    onRetry = onLocateNow,
                )

                is LocateUiState.Polling -> {
                    FindlyStatusChip(label = "Waiting for a response…", tone = FindlyStatusTone.Neutral)
                    state.lastKnown?.let { lastKnown ->
                        FindlyCard {
                            FindlyListRow(
                                title = "Last known",
                                subtitle = "${lastKnown.lat}, ${lastKnown.lon} · ${lastKnown.recordedAt}",
                            )
                        }
                    }
                    FindlyLoadingState(message = "Polling…")
                }

                is LocateUiState.Terminal -> {
                    val (label, tone) = when (state.status) {
                        "fulfilled" -> "Located" to FindlyStatusTone.Success
                        "pushFailed" -> "Couldn't reach the device — showing last known" to FindlyStatusTone.Warning
                        else -> "Request expired" to FindlyStatusTone.Neutral
                    }
                    FindlyStatusChip(label = label, tone = tone)

                    val point = state.fix?.let { it.lat to it.lon } ?: state.lastKnown?.let { it.lat to it.lon }
                    if (point != null) {
                        FindlyCard {
                            FindlyListRow(
                                title = "Location",
                                subtitle = "${point.first}, ${point.second}",
                            )
                        }
                    }

                    FindlyButton(text = "Locate again", onClick = onLocateNow)
                }
            }
        }
    }
}

@Preview(name = "Locate — light", showBackground = true)
@Composable
private fun LocateScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        LocateScreen(
            state = LocateUiState.Terminal(
                requestId = "lr_preview",
                status = "fulfilled",
                fix = LocateFixUi("d1", 51.0544, 3.7170, 4.8, "2026-07-19T09:05:12Z", 77),
                lastKnown = null,
            ),
            targetDisplayName = "Noor",
        )
    }
}

@Preview(name = "Locate — dark", showBackground = true)
@Composable
private fun LocateScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        LocateScreen(state = LocateUiState.Idle, targetDisplayName = "Noor")
    }
}
