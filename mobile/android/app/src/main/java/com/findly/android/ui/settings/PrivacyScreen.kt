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
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlySectionHeader
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * The Privacy & data screen (specs/010-app-shell-and-screen-ux.md §4.1's `Privacy & data` drawer
 * destination), extracted from the retired `ui/settings/SettingsScreen.kt` monolith — this is
 * exactly that file's former `PrivacySection`/dialogs, now its own route rather than an
 * unconditional block rendered below the Devices/Family content (which is also what produced
 * that file's own off-screen-content layout bug: two sibling `fillMaxSize()` `Column`s starving
 * each other, the same shape as `MapScreen.kt`'s pre-010 roster bug). [PrivacyStateHolder]/
 * [PrivacyUiState]/[PrivacyViewModel] are unchanged — export/delete-account/delete-family were
 * already independent of the family/device load (see [PrivacyStateHolder]'s doc), so nothing
 * about their logic needed to move, only where the screen renders them.
 */
@Composable
fun PrivacyRoute(
    viewModel: PrivacyViewModel,
    modifier: Modifier = Modifier,
    onRouteToOnboarding: (OnboardingVariant) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    // 001 §13.1 / specs/003 §12.4: the export body is handed to the OS share/save sheet unparsed,
    // exactly once per successful export — ExportFileWriter is the one place it touches disk.
    LaunchedEffect(state.exportFlow) {
        val ready = state.exportFlow as? ExportFlow.Ready ?: return@LaunchedEffect
        val intent = ExportFileWriter.buildShareIntent(context, ready.result)
        context.startActivity(intent)
        viewModel.dismissExportResult()
    }

    LaunchedEffect(state.exportRouteToOnboarding) {
        state.exportRouteToOnboarding?.let(onRouteToOnboarding)
    }

    PrivacyScreen(
        state = state,
        onExportSelf = viewModel::exportSelf,
        onExportMember = viewModel::exportMember,
        onDismissExportError = viewModel::dismissExportResult,
        onStartDeleteAccount = viewModel::startDeleteAccount,
        onAdvanceDeleteAccountConfirmation = viewModel::advanceDeleteAccountConfirmation,
        onCancelDeleteAccount = viewModel::cancelDeleteAccount,
        onConfirmDeleteAccount = viewModel::confirmDeleteAccount,
        onSignOutAfterFirebaseFailure = viewModel::signOutAfterFirebaseFailure,
        onStartDeleteFamily = viewModel::startDeleteFamily,
        onUpdateDeleteFamilyTypedName = viewModel::updateDeleteFamilyTypedName,
        onCancelDeleteFamily = viewModel::cancelDeleteFamily,
        onConfirmDeleteFamily = viewModel::confirmDeleteFamily,
        modifier = modifier,
    )
}

@Composable
fun PrivacyScreen(
    state: PrivacyUiState,
    modifier: Modifier = Modifier,
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
        FindlyTopBar(title = "Privacy & data")

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
        ) {
            PrivacySection(
                state = state,
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
 * Export / delete-account / delete-family (001 §13; specs/008-privacy-endpoints.md; specs/003-
 * android-client.md §12.4). Confirm dialogs use Material3's [AlertDialog] directly — the same
 * documented exception `GroupDetailScreen`'s owner-action confirms use (specs/003 §4.3 exception
 * 2) — since the actual two-step **gating** (no network call before the final confirm) is already
 * enforced by [PrivacyStateHolder]'s state machine, not by anything in this Composable.
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
 * then re-running delete-account from Privacy & data, is the only real recovery). */
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

@Preview(name = "Privacy — light", showBackground = true)
@Composable
private fun PrivacyScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        PrivacyScreen(
            state = PrivacyUiState(
                isLoadingFamily = false,
                isParent = true,
                isSoleParent = true,
                familyName = "Wauters",
                exportableMembers = listOf(ExportableMemberUi("u2", "Noor")),
            ),
        )
    }
}

@Preview(name = "Privacy — dark", showBackground = true)
@Composable
private fun PrivacyScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        PrivacyScreen(state = PrivacyUiState())
    }
}
