package com.findly.android.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
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
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * The A2 device/family-settings screen (001-api-contract.md §3.5/§3.6/§4.2/§4.3, specs/003-
 * android-client.md §12's `Settings` destination): device list with pause/sync-interval controls
 * and member roster with role/remove controls, gated on [SettingsUiState.Content.myRole] — a
 * non-parent sees everything read-only.
 *
 * **A8 addition** (001 §13; specs/008-privacy-endpoints.md; specs/003 §12.4): the privacy section
 * (export / delete account / delete family) is driven by an entirely separate [PrivacyViewModel]/
 * [PrivacyStateHolder] and is rendered unconditionally below the devices/members content — even
 * when [SettingsUiState] itself is [SettingsUiState.Error] (e.g. a family-less or profile-less
 * caller gets `FAMILY_NOT_FOUND`/`PROFILE_NOT_FOUND` from `GET /families/me`). This is what makes
 * "delete account" reachable without contacting support (008 §4.4) regardless of family state.
 */
@Composable
fun SettingsRoute(
    viewModel: SettingsViewModel,
    privacyViewModel: PrivacyViewModel,
    modifier: Modifier = Modifier,
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val privacyState by privacyViewModel.state.collectAsState()
    val context = LocalContext.current

    // 001 §13.1 / specs/003 §12.4: the export body is handed to the OS share/save sheet unparsed,
    // exactly once per successful export — ExportFileWriter is the one place it touches disk.
    // 008 §3.1 rule 2 (amended): the artifact is deliberately NOT cleared on the chooser's return,
    // dismissal, or this screen's teardown — an implicit ACTION_SEND chooser's activity-result
    // callback fires as soon as the target activity is *launched*, not once it has finished
    // reading the content:// bytes, so clearing on that signal would race and silently corrupt
    // lazily-reading share targets ("Save to Files"/"Save to Drive"). Cleanup instead happens
    // before the next write (ExportArtifactStore.write, below), on the next cold start
    // (AppContainer's startup wipe), and via the account-deletion local wipe.
    LaunchedEffect(privacyState.exportFlow) {
        val ready = privacyState.exportFlow as? ExportFlow.Ready ?: return@LaunchedEffect
        val intent = ExportFileWriter.buildShareIntent(context, ready.result)
        context.startActivity(intent)
        privacyViewModel.dismissExportResult()
    }

    // specs/010-app-shell-and-screen-ux.md §2.1's routing rule — Settings' own load (Devices +
    // Family) and the Privacy section's export action each carry their own routing outcome; both
    // funnel into the one callback the caller supplied.
    LaunchedEffect(state) {
        val current = state
        if (current is SettingsUiState.RouteToOnboarding) onRouteToOnboarding(current.variant)
    }
    LaunchedEffect(privacyState.exportRouteToOnboarding) {
        privacyState.exportRouteToOnboarding?.let(onRouteToOnboarding)
    }

    SettingsScreen(
        state = state,
        privacyState = privacyState,
        onTogglePause = { deviceId, enabled -> viewModel.updateDeviceSettings(deviceId, trackingEnabled = enabled) },
        onPromote = { userId -> viewModel.updateMemberRole(userId, role = "parent") },
        onDemote = { userId -> viewModel.updateMemberRole(userId, role = "member") },
        onRemoveMember = viewModel::removeMember,
        onRetry = viewModel::reload,
        onExportSelf = privacyViewModel::exportSelf,
        onExportMember = privacyViewModel::exportMember,
        onDismissExportError = privacyViewModel::dismissExportResult,
        onStartDeleteAccount = privacyViewModel::startDeleteAccount,
        onAdvanceDeleteAccountConfirmation = privacyViewModel::advanceDeleteAccountConfirmation,
        onCancelDeleteAccount = privacyViewModel::cancelDeleteAccount,
        onConfirmDeleteAccount = privacyViewModel::confirmDeleteAccount,
        onSignOutAfterFirebaseFailure = privacyViewModel::signOutAfterFirebaseFailure,
        onStartDeleteFamily = privacyViewModel::startDeleteFamily,
        onUpdateDeleteFamilyTypedName = privacyViewModel::updateDeleteFamilyTypedName,
        onCancelDeleteFamily = privacyViewModel::cancelDeleteFamily,
        onConfirmDeleteFamily = privacyViewModel::confirmDeleteFamily,
        modifier = modifier,
    )
}

@Composable
fun SettingsScreen(
    state: SettingsUiState,
    modifier: Modifier = Modifier,
    privacyState: PrivacyUiState = PrivacyUiState(),
    onTogglePause: (deviceId: String, trackingEnabled: Boolean) -> Unit = { _, _ -> },
    onPromote: (userId: String) -> Unit = {},
    onDemote: (userId: String) -> Unit = {},
    onRemoveMember: (userId: String) -> Unit = {},
    onRetry: () -> Unit = {},
    onExportSelf: () -> Unit = {},
    onExportMember: (userId: String) -> Unit = {},
    onDismissExportError: () -> Unit = {},
    onStartDeleteAccount: () -> Unit = {},
    onAdvanceDeleteAccountConfirmation: () -> Unit = {},
    onCancelDeleteAccount: () -> Unit = {},
    onConfirmDeleteAccount: () -> Unit = {},
    onSignOutAfterFirebaseFailure: () -> Unit = {},
    onStartDeleteFamily: () -> Unit = {},
    onUpdateDeleteFamilyTypedName: (String) -> Unit = {},
    onCancelDeleteFamily: () -> Unit = {},
    onConfirmDeleteFamily: () -> Unit = {},
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

            is SettingsUiState.RouteToOnboarding -> FindlyLoadingState(message = "Loading…")

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

        // A8: unconditional — see this file's top doc for why this never sits behind `state`.
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
        ) {
            PrivacySection(
                state = privacyState,
                onExportSelf = onExportSelf,
                onExportMember = onExportMember,
                onDismissExportError = onDismissExportError,
                onStartDeleteAccount = onStartDeleteAccount,
                onAdvanceDeleteAccountConfirmation = onAdvanceDeleteAccountConfirmation,
                onCancelDeleteAccount = onCancelDeleteAccount,
                onConfirmDeleteAccount = onConfirmDeleteAccount,
                onSignOutAfterFirebaseFailure = onSignOutAfterFirebaseFailure,
                onStartDeleteFamily = onStartDeleteFamily,
                onUpdateDeleteFamilyTypedName = onUpdateDeleteFamilyTypedName,
                onCancelDeleteFamily = onCancelDeleteFamily,
                onConfirmDeleteFamily = onConfirmDeleteFamily,
            )
        }
    }
}

/**
 * Export / delete-account / delete-family (001 §13; specs/008-privacy-endpoints.md;
 * specs/003-android-client.md §12.4). Confirm dialogs use Material3's [AlertDialog] directly —
 * the same documented exception `GroupDetailScreen`'s owner-action confirms use (specs/003 §4.3
 * exception 2) — since the actual two-step **gating** (no network call before the final confirm)
 * is already enforced by [PrivacyStateHolder]'s state machine, not by anything in this Composable.
 */
@Composable
private fun PrivacySection(
    state: PrivacyUiState,
    onExportSelf: () -> Unit,
    onExportMember: (userId: String) -> Unit,
    onDismissExportError: () -> Unit,
    onStartDeleteAccount: () -> Unit,
    onAdvanceDeleteAccountConfirmation: () -> Unit,
    onCancelDeleteAccount: () -> Unit,
    onConfirmDeleteAccount: () -> Unit,
    onSignOutAfterFirebaseFailure: () -> Unit,
    onStartDeleteFamily: () -> Unit,
    onUpdateDeleteFamilyTypedName: (String) -> Unit,
    onCancelDeleteFamily: () -> Unit,
    onConfirmDeleteFamily: () -> Unit,
) {
    FindlySectionHeader(title = "Privacy")

    val exportFlow = state.exportFlow
    if (exportFlow is ExportFlow.Failed) {
        FindlyStatusChip(label = exportFlow.message, tone = FindlyStatusTone.Danger)
    }

    FindlyListRow(
        title = "Export my data",
        subtitle = "Download a copy of everything Findly holds about you",
        trailing = {
            FindlyButton(
                text = if (state.exportFlow is ExportFlow.Exporting) "Exporting…" else "Export",
                onClick = onExportSelf,
                enabled = state.exportFlow !is ExportFlow.Exporting,
                style = FindlyButtonStyle.Secondary,
            )
        },
    )
    if (state.exportFlow is ExportFlow.Failed) {
        FindlyButton(text = "Dismiss", onClick = onDismissExportError, style = FindlyButtonStyle.Secondary)
    }

    if (state.isParent && state.exportableMembers.isNotEmpty()) {
        state.exportableMembers.forEach { member ->
            FindlyListRow(
                title = "Export ${member.displayName}'s data",
                trailing = {
                    FindlyButton(
                        text = "Export",
                        onClick = { onExportMember(member.userId) },
                        enabled = state.exportFlow !is ExportFlow.Exporting,
                        style = FindlyButtonStyle.Secondary,
                    )
                },
            )
        }
    }

    FindlyListRow(
        title = "Delete my account",
        subtitle = "Permanently erases your account and its data",
        trailing = {
            FindlyButton(text = "Delete", onClick = onStartDeleteAccount, style = FindlyButtonStyle.Secondary)
        },
    )

    if (state.isParent) {
        FindlyListRow(
            title = "Delete family",
            subtitle = "Permanently erases the whole family's history for everyone",
            trailing = {
                FindlyButton(text = "Delete", onClick = onStartDeleteFamily, style = FindlyButtonStyle.Secondary)
            },
        )
    }

    DeleteAccountDialogs(
        flow = state.deleteAccountFlow,
        onAdvance = onAdvanceDeleteAccountConfirmation,
        onCancel = onCancelDeleteAccount,
        onConfirm = onConfirmDeleteAccount,
        onSignOutAfterFirebaseFailure = onSignOutAfterFirebaseFailure,
    )

    DeleteFamilyDialog(
        flow = state.deleteFamilyFlow,
        onTypedNameChange = onUpdateDeleteFamilyTypedName,
        onCancel = onCancelDeleteFamily,
        onConfirm = onConfirmDeleteFamily,
    )
}

/** The two-step delete-account confirm (specs/008-privacy-endpoints.md §4.4) — [DeleteAccountFlow]
 * itself is what prevents a network call before the second dialog's confirm button. The
 * [DeleteAccountFlow.FirebaseRetryNeeded] dialog offers sign-out, never a bare retry (008 §1.3 —
 * a retry is a trap: `requires-recent-login` never clears on its own; signing out and back in,
 * then re-running delete-account from Settings, is the only real recovery). */
@Composable
private fun DeleteAccountDialogs(
    flow: DeleteAccountFlow,
    onAdvance: () -> Unit,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
    onSignOutAfterFirebaseFailure: () -> Unit,
) {
    when (flow) {
        is DeleteAccountFlow.Step1Confirming -> AlertDialog(
            onDismissRequest = onCancel,
            title = { Text("Delete your account?") },
            text = {
                Text(
                    "This permanently deletes your account, devices, and location history." +
                        if (flow.cascadeWarning) {
                            " You are the only parent — this deletes the family for everyone."
                        } else {
                            ""
                        },
                )
            },
            confirmButton = { FindlyButton(text = "Continue", onClick = onAdvance) },
            dismissButton = { FindlyButton(text = "Cancel", onClick = onCancel, style = FindlyButtonStyle.Secondary) },
        )

        is DeleteAccountFlow.Step2Confirming -> AlertDialog(
            onDismissRequest = onCancel,
            title = { Text("Are you sure?") },
            text = { Text("This cannot be undone. Your account and its data will be permanently deleted.") },
            confirmButton = { FindlyButton(text = "Delete my account", onClick = onConfirm) },
            dismissButton = { FindlyButton(text = "Cancel", onClick = onCancel, style = FindlyButtonStyle.Secondary) },
        )

        is DeleteAccountFlow.Deleting -> AlertDialog(
            onDismissRequest = {},
            title = { Text("Deleting your account…") },
            text = { Text("Please wait.") },
            confirmButton = {},
        )

        DeleteAccountFlow.FirebaseRetryNeeded -> AlertDialog(
            onDismissRequest = {},
            title = { Text("Almost done") },
            text = {
                Text(
                    "Your data has already been deleted, but we couldn't finish signing you out " +
                        "of this device. Sign out now, then sign back in and delete your account " +
                        "again to finish — it won't create anything new.",
                )
            },
            confirmButton = { FindlyButton(text = "Sign out", onClick = onSignOutAfterFirebaseFailure) },
        )

        is DeleteAccountFlow.Failed -> AlertDialog(
            onDismissRequest = onCancel,
            title = { Text("Couldn't delete your account") },
            text = { Text(flow.message) },
            confirmButton = { FindlyButton(text = "OK", onClick = onCancel) },
        )

        DeleteAccountFlow.Idle -> Unit
    }
}

/** The two-step delete-family confirm, requiring the family name to be typed exactly
 * (specs/008-privacy-endpoints.md §5.4). */
@Composable
private fun DeleteFamilyDialog(
    flow: DeleteFamilyFlow,
    onTypedNameChange: (String) -> Unit,
    onCancel: () -> Unit,
    onConfirm: () -> Unit,
) {
    when (flow) {
        is DeleteFamilyFlow.Confirming -> AlertDialog(
            onDismissRequest = onCancel,
            title = { Text("Delete this family?") },
            text = {
                Column {
                    Text(
                        "This permanently erases the whole family's history for every member. " +
                            "Type \"${flow.familyName}\" to confirm.",
                    )
                    FindlyTextField(
                        value = flow.typedName,
                        onValueChange = onTypedNameChange,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = flow.familyName,
                    )
                }
            },
            confirmButton = {
                FindlyButton(
                    text = "Delete family",
                    onClick = onConfirm,
                    enabled = flow.typedName.trim() == flow.familyName,
                )
            },
            dismissButton = { FindlyButton(text = "Cancel", onClick = onCancel, style = FindlyButtonStyle.Secondary) },
        )

        is DeleteFamilyFlow.Deleting -> AlertDialog(
            onDismissRequest = {},
            title = { Text("Deleting family…") },
            text = { Text("Please wait.") },
            confirmButton = {},
        )

        is DeleteFamilyFlow.Failed -> AlertDialog(
            onDismissRequest = onCancel,
            title = { Text("Couldn't delete the family") },
            text = { Text(flow.message) },
            confirmButton = { FindlyButton(text = "OK", onClick = onCancel) },
        )

        DeleteFamilyFlow.Idle -> Unit
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
            privacyState = PrivacyUiState(
                isLoadingFamily = false,
                isParent = true,
                isSoleParent = true,
                familyName = "Wauters",
                exportableMembers = listOf(ExportableMemberUi("u2", "Noor")),
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
