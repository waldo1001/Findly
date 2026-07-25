package com.findly.android.ui.settings

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
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlySectionHeader
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlySwitchRow
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The A2 device/family-settings screen (001-api-contract.md §3.5/§3.6/§4.2/§4.3, specs/003-
 * android-client.md §12's `Settings` destination): device list with pause/sync-interval controls
 * and member roster with role/remove controls, gated on [SettingsUiState.Content.myRole] — a
 * non-parent sees everything read-only.
 */
@Composable
fun SettingsRoute(viewModel: SettingsViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    SettingsScreen(
        state = state,
        onTogglePause = { deviceId, enabled -> viewModel.updateDeviceSettings(deviceId, trackingEnabled = enabled) },
        onPromote = { userId -> viewModel.updateMemberRole(userId, role = "parent") },
        onDemote = { userId -> viewModel.updateMemberRole(userId, role = "member") },
        onRemoveMember = viewModel::removeMember,
        onRetry = viewModel::reload,
        modifier = modifier,
    )
}

@Composable
fun SettingsScreen(
    state: SettingsUiState,
    modifier: Modifier = Modifier,
    onTogglePause: (deviceId: String, trackingEnabled: Boolean) -> Unit = { _, _ -> },
    onPromote: (userId: String) -> Unit = {},
    onDemote: (userId: String) -> Unit = {},
    onRemoveMember: (userId: String) -> Unit = {},
    onRetry: () -> Unit = {},
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Settings")

        when (state) {
            is SettingsUiState.Loading -> FindlyLoadingState(message = "Loading…")

            is SettingsUiState.Error -> FindlyErrorState(
                title = "Couldn't load settings",
                message = state.message,
                onRetry = onRetry,
            )

            is SettingsUiState.Content -> {
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

                    FindlySectionHeader(title = "Devices")
                    state.devices.forEach { device ->
                        FindlySwitchRow(
                            title = "${device.ownerDisplayName} · ${device.deviceName}",
                            subtitle = "Every ${device.syncIntervalMinutes} min" +
                                if (device.pushInvalid) " · push token invalid" else "",
                            checked = device.trackingEnabled,
                            enabled = isParent && !state.isMutating,
                            onCheckedChange = { onTogglePause(device.deviceId, it) },
                        )
                    }

                    FindlySectionHeader(title = "Members")
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

@Preview(name = "Settings — light", showBackground = true)
@Composable
private fun SettingsScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        SettingsScreen(
            state = SettingsUiState.Content(
                myRole = "parent",
                members = listOf(
                    MemberUi("u1", "parent", "Eric", "2026-07-01T00:00:00Z"),
                    MemberUi("u2", "member", "Noor", "2026-07-02T00:00:00Z"),
                ),
                devices = listOf(
                    DeviceUi("d1", "Pixel 8", "Pixel 8", "android", 15, true, false, "Eric", "2026-07-19T09:05:14Z"),
                ),
            ),
        )
    }
}

@Preview(name = "Settings — dark", showBackground = true)
@Composable
private fun SettingsScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        SettingsScreen(state = SettingsUiState.Loading)
    }
}
