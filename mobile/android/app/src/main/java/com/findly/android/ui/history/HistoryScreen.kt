package com.findly.android.ui.history

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant
import java.time.Instant
import java.time.ZoneOffset

/**
 * The A2 history screen (001-api-contract.md §5.3, specs/003-android-client.md §12's `History`
 * destination): a date-range picker + `userId`/optional-`deviceId` filter, a cursor-paginated
 * point list, driven by [HistoryViewModel]/[HistoryStateHolder]. The date pickers use Material3's
 * [DatePickerDialog] directly — one of the "un-migrated Material3 primitives" `FindlyTheme`
 * explicitly themes (specs/003 §4.3's `FindlyTheme` doc), not a design-system component, since
 * re-implementing a calendar widget is out of scope; its action buttons are still [FindlyButton]s.
 */
@Composable
fun HistoryRoute(
    viewModel: HistoryViewModel,
    modifier: Modifier = Modifier,
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    HistoryScreen(
        state = state,
        onQuery = viewModel::load,
        onLoadMore = viewModel::loadMore,
        onRouteToOnboarding = onRouteToOnboarding,
        modifier = modifier,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    state: HistoryUiState,
    modifier: Modifier = Modifier,
    onQuery: (userId: String, from: String, to: String, deviceId: String?) -> Unit = { _, _, _, _ -> },
    onLoadMore: () -> Unit = {},
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule.
    LaunchedEffect(state) {
        if (state is HistoryUiState.RouteToOnboarding) onRouteToOnboarding(state.variant)
    }

    var userId by remember { mutableStateOf("") }
    var deviceId by remember { mutableStateOf("") }
    var fromDate by remember { mutableStateOf<String?>(null) }
    var toDate by remember { mutableStateOf<String?>(null) }
    var showFromPicker by remember { mutableStateOf(false) }
    var showToPicker by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "History")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            FindlyTextField(value = userId, onValueChange = { userId = it }, label = "User ID")
            FindlyTextField(
                value = deviceId,
                onValueChange = { deviceId = it },
                label = "Device ID (optional — all devices when blank)",
            )

            Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                FindlyButton(
                    text = fromDate?.let { "From: $it" } ?: "Pick from date",
                    onClick = { showFromPicker = true },
                    style = FindlyButtonStyle.Secondary,
                )
                FindlyButton(
                    text = toDate?.let { "To: $it" } ?: "Pick to date",
                    onClick = { showToPicker = true },
                    style = FindlyButtonStyle.Secondary,
                )
            }

            val from = fromDate
            val to = toDate
            FindlyButton(
                text = "Search",
                enabled = userId.isNotBlank() && from != null && to != null,
                onClick = {
                    if (from != null && to != null) {
                        onQuery(userId, from, to, deviceId.ifBlank { null })
                    }
                },
            )
        }

        when (state) {
            is HistoryUiState.Idle ->
                FindlyEmptyState(title = "No query yet", message = "Choose a user and date range, then search.")

            is HistoryUiState.Loading -> FindlyLoadingState(message = "Loading history…")

            is HistoryUiState.Error -> FindlyErrorState(title = "Couldn't load history", message = state.message)

            is HistoryUiState.RouteToOnboarding -> FindlyLoadingState(message = "Loading history…")

            is HistoryUiState.Content -> {
                if (state.points.isEmpty()) {
                    FindlyEmptyState(title = "No history", message = "Nothing recorded in that range.")
                } else {
                    LazyColumn(
                        modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md),
                        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
                    ) {
                        items(state.points, key = { "${it.deviceId}-${it.recordedAt}" }) { point ->
                            FindlyListRow(
                                title = point.recordedAt,
                                subtitle = "${point.lat}, ${point.lon} · ${point.source} · ${point.batteryPct}%",
                            )
                        }
                        if (state.nextCursor != null) {
                            item(key = "load-more") {
                                FindlyButton(
                                    text = if (state.isLoadingMore) "Loading…" else "Load more",
                                    enabled = !state.isLoadingMore,
                                    onClick = onLoadMore,
                                    style = FindlyButtonStyle.Secondary,
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showFromPicker) {
        val pickerState = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showFromPicker = false },
            confirmButton = {
                FindlyButton(
                    text = "OK",
                    onClick = {
                        pickerState.selectedDateMillis?.let { fromDate = it.toIsoDate() }
                        showFromPicker = false
                    },
                )
            },
            dismissButton = { FindlyButton(text = "Cancel", onClick = { showFromPicker = false }, style = FindlyButtonStyle.Secondary) },
        ) { DatePicker(state = pickerState) }
    }

    if (showToPicker) {
        val pickerState = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showToPicker = false },
            confirmButton = {
                FindlyButton(
                    text = "OK",
                    onClick = {
                        pickerState.selectedDateMillis?.let { toDate = it.toIsoDate() }
                        showToPicker = false
                    },
                )
            },
            dismissButton = { FindlyButton(text = "Cancel", onClick = { showToPicker = false }, style = FindlyButtonStyle.Secondary) },
        ) { DatePicker(state = pickerState) }
    }
}

/** Epoch millis (UTC, as `DatePickerState` always reports) to a §5.3 `YYYY-MM-DD` device-agnostic
 * UTC date string. */
private fun Long.toIsoDate(): String = Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate().toString()

@Preview(name = "History — light", showBackground = true)
@Composable
private fun HistoryScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        HistoryScreen(
            state = HistoryUiState.Content(
                points = listOf(
                    HistoryPointUi("d1", "2026-07-19T09:05:12Z", 51.05, 3.71, 12.5, 78, "periodic"),
                ),
                nextCursor = null,
            ),
        )
    }
}

@Preview(name = "History — dark", showBackground = true)
@Composable
private fun HistoryScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        HistoryScreen(state = HistoryUiState.Idle)
    }
}
