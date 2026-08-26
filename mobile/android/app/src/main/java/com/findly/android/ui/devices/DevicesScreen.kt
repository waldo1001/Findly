package com.findly.android.ui.devices

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.network.PlanLimits
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyDropdownField
import com.findly.android.ui.designsystem.components.FindlyEmptyState
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlySwitchRow
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * The Devices screen (specs/010-app-shell-and-screen-ux.md §4) — Android's first real Devices UI,
 * extracted from the retired `ui/settings/SettingsScreen.kt` monolith. Per-device card, §4.2:
 * header (name + status chip), owner line, parent-only tracking toggle / sync-interval dropdown /
 * rename row, and per-card error placement (never a shared top-of-list banner).
 */
@Composable
fun DevicesRoute(
    viewModel: DevicesViewModel,
    modifier: Modifier = Modifier,
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(state) {
        val current = state
        if (current is DevicesUiState.RouteToOnboarding) onRouteToOnboarding(current.variant)
    }

    DevicesScreen(
        state = state,
        isParent = viewModel.isParent,
        onRetry = viewModel::reload,
        onToggleTracking = viewModel::setTracking,
        onSelectSyncInterval = viewModel::setSyncInterval,
        onRenameDraftChange = viewModel::updateRenameDraft,
        onSaveRename = viewModel::rename,
        modifier = modifier,
    )
}

@Composable
fun DevicesScreen(
    state: DevicesUiState,
    modifier: Modifier = Modifier,
    isParent: Boolean = false,
    onRetry: () -> Unit = {},
    onToggleTracking: (deviceId: String, enabled: Boolean) -> Unit = { _, _ -> },
    onSelectSyncInterval: (deviceId: String, minutes: Int) -> Unit = { _, _ -> },
    onRenameDraftChange: (deviceId: String, draft: String) -> Unit = { _, _ -> },
    onSaveRename: (deviceId: String, name: String) -> Unit = { _, _ -> },
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Devices")

        when (state) {
            is DevicesUiState.Loading -> FindlyLoadingState(message = "Loading…")

            is DevicesUiState.Error -> FindlyErrorState(
                title = "Couldn't load devices",
                message = state.message,
                onRetry = onRetry,
            )

            is DevicesUiState.RouteToOnboarding -> FindlyLoadingState(message = "Loading…")

            is DevicesUiState.Content -> {
                if (state.devices.isEmpty()) {
                    FindlyEmptyState(
                        title = "No devices yet",
                        message = "Devices register automatically after sign-in.",
                        modifier = Modifier.padding(FindlyTheme.spacing.md),
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(FindlyTheme.spacing.md),
                        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
                    ) {
                        items(state.devices, key = { it.deviceId }) { device ->
                            DeviceCard(
                                device = device,
                                isParent = isParent,
                                limits = state.limits,
                                onToggleTracking = { enabled -> onToggleTracking(device.deviceId, enabled) },
                                onSelectSyncInterval = { minutes -> onSelectSyncInterval(device.deviceId, minutes) },
                                onRenameDraftChange = { draft -> onRenameDraftChange(device.deviceId, draft) },
                                onSaveRename = { onSaveRename(device.deviceId, device.renameDraft.trim()) },
                            )
                        }
                    }
                }
            }
        }
    }
}

/** One §4.2 device card. Top to bottom: header row (name + Active/Paused chip), owner line,
 * parent-only controls (tracking toggle, sync-interval dropdown, the single aligned rename row),
 * this card's own mutation error. A non-parent sees only the first two, read-only. */
@Composable
private fun DeviceCard(
    device: DeviceCardUi,
    isParent: Boolean,
    limits: PlanLimits?,
    onToggleTracking: (Boolean) -> Unit,
    onSelectSyncInterval: (Int) -> Unit,
    onRenameDraftChange: (String) -> Unit,
    onSaveRename: () -> Unit,
) {
    FindlyCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(text = device.deviceName, color = FindlyTheme.colors.onSurface, style = FindlyTheme.typography.titleMedium)
            FindlyStatusChip(
                label = if (device.trackingEnabled) "Active" else "Paused",
                tone = if (device.trackingEnabled) FindlyStatusTone.Success else FindlyStatusTone.Neutral,
            )
        }

        Text(
            text = "Owner: ${device.ownerDisplayName}",
            color = FindlyTheme.colors.subtleText,
            style = FindlyTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = FindlyTheme.spacing.xs, bottom = FindlyTheme.spacing.sm),
        )

        if (isParent) {
            FindlySwitchRow(
                title = "Tracking",
                checked = device.trackingEnabled,
                onCheckedChange = onToggleTracking,
                enabled = !device.isMutating,
            )

            FindlyDropdownField(
                label = "Sync interval",
                selected = device.syncIntervalMinutes,
                options = SyncIntervalOptions.buildForLimits(limits),
                onSelect = onSelectSyncInterval,
                // Fail closed (review-round fix): a null `limits` -- spec-unreachable today,
                // 003 sec6.2 -- must never fall back to an unrestricted floor. buildForLimits
                // already disables every option in that case; disabling the whole field too
                // means there is nothing left to tap, not just nothing selectable.
                enabled = !device.isMutating && limits != null,
                modifier = Modifier.padding(top = FindlyTheme.spacing.sm),
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = FindlyTheme.spacing.sm),
                horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FindlyTextField(
                    value = device.renameDraft,
                    onValueChange = onRenameDraftChange,
                    placeholder = "Device name",
                    enabled = !device.isMutating,
                    modifier = Modifier.weight(1f),
                )
                FindlyButton(
                    text = "Save",
                    onClick = onSaveRename,
                    enabled = !device.isMutating &&
                        device.renameDraft.trim().isNotEmpty() &&
                        device.renameDraft.trim() != device.deviceName,
                    style = FindlyButtonStyle.Secondary,
                )
            }
        }

        if (device.error != null) {
            Text(
                text = device.error,
                color = FindlyTheme.colors.danger,
                style = FindlyTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = FindlyTheme.spacing.sm),
            )
        }
    }
}

@Preview(name = "Devices — light", showBackground = true)
@Composable
private fun DevicesScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        DevicesScreen(
            isParent = true,
            state = DevicesUiState.Content(
                devices = listOf(
                    DeviceCardUi(
                        deviceId = "d1",
                        deviceName = "Pixel 8",
                        model = "Pixel 8",
                        platform = "android",
                        syncIntervalMinutes = 15,
                        trackingEnabled = true,
                        pushInvalid = false,
                        ownerDisplayName = "Eric",
                        lastSeenAt = "2026-07-19T09:05:14Z",
                    ),
                    DeviceCardUi(
                        deviceId = "d2",
                        deviceName = "Noor's tablet",
                        model = "iPad",
                        platform = "ios",
                        syncIntervalMinutes = 60,
                        trackingEnabled = false,
                        pushInvalid = false,
                        ownerDisplayName = "Noor",
                        lastSeenAt = "2026-07-19T08:00:00Z",
                        error = "Something went wrong on our end. Please try again.",
                    ),
                ),
                limits = PlanLimits(
                    maxDevices = 10,
                    maxGeofences = 20,
                    historyDays = 90,
                    minSyncIntervalMinutes = 15,
                    locateRequestsPerDay = 100,
                ),
            ),
        )
    }
}

@Preview(name = "Devices — empty", showBackground = true)
@Composable
private fun DevicesScreenEmptyPreview() {
    FindlyTheme(darkTheme = false) {
        DevicesScreen(state = DevicesUiState.Content(devices = emptyList(), limits = null))
    }
}

@Preview(name = "Devices — dark", showBackground = true)
@Composable
private fun DevicesScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        DevicesScreen(state = DevicesUiState.Loading)
    }
}
