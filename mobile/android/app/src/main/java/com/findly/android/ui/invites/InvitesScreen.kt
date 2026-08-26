package com.findly.android.ui.invites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * The A2 invites screen (001-api-contract.md §3.3/§3.4, specs/003-android-client.md §12): create
 * an invite (parent, shared out-of-band per §3.3) and accept an invite (join a family, §3.4) —
 * two independent forms on one screen, driven by [InvitesViewModel]/[InvitesStateHolder].
 *
 * [onAccepted] (A24) fires once per successful accept — [state.acceptedFamily] is the only
 * bootstrap-completion signal this screen has, since (unlike [com.findly.android.ui.family.CreateFamilyScreen]/
 * [com.findly.android.ui.groups.CreateGroupScreen]/[com.findly.android.ui.groups.GroupJoinScreen])
 * it does not navigate away on success. Deliberately does **not** trigger on [state.createdInvite]
 * — creating an invite (parent, already-profiled) never bootstraps a profile.
 */
@Composable
fun InvitesRoute(
    viewModel: InvitesViewModel,
    modifier: Modifier = Modifier,
    prefillDisplayName: String = "",
    onAccepted: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    InvitesScreen(
        state = state,
        prefillDisplayName = prefillDisplayName,
        onCreateInvite = viewModel::createInvite,
        onAcceptInvite = viewModel::acceptInvite,
        onAccepted = onAccepted,
        modifier = modifier,
    )
}

@Composable
fun InvitesScreen(
    state: InvitesUiState,
    modifier: Modifier = Modifier,
    prefillDisplayName: String = "",
    onCreateInvite: (role: String, emailHint: String?) -> Unit = { _, _ -> },
    onAcceptInvite: (inviteCode: String, displayName: String) -> Unit = { _, _ -> },
    onAccepted: () -> Unit = {},
) {
    var selectedRole by remember { mutableStateOf("member") }
    var emailHint by remember { mutableStateOf("") }
    var inviteCode by remember { mutableStateOf("") }
    // A21: seeded from the profile-less first-run screen's shared display-name entry
    // (now specs/010's Onboarding screen) when reached from "I have an invite code".
    var displayName by remember { mutableStateOf(prefillDisplayName) }

    LaunchedEffect(state.acceptedFamily) {
        if (state.acceptedFamily != null) onAccepted()
    }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Invites")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.lg),
        ) {
            FindlyCard {
                Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                        FindlyButton(
                            text = "Member",
                            onClick = { selectedRole = "member" },
                            style = if (selectedRole == "member") FindlyButtonStyle.Primary else FindlyButtonStyle.Secondary,
                        )
                        FindlyButton(
                            text = "Parent",
                            onClick = { selectedRole = "parent" },
                            style = if (selectedRole == "parent") FindlyButtonStyle.Primary else FindlyButtonStyle.Secondary,
                        )
                    }
                    FindlyTextField(value = emailHint, onValueChange = { emailHint = it }, label = "Email hint (optional)")
                    FindlyButton(
                        text = if (state.isCreatingInvite) "Creating…" else "Create invite",
                        enabled = !state.isCreatingInvite,
                        onClick = { onCreateInvite(selectedRole, emailHint.ifBlank { null }) },
                    )
                    state.createdInvite?.let { invite ->
                        FindlyStatusChip(label = "Code: ${invite.inviteCode} · expires ${invite.expiresAt}", tone = FindlyStatusTone.Success)
                    }
                    state.createInviteError?.let { error ->
                        FindlyStatusChip(label = error, tone = FindlyStatusTone.Danger)
                    }
                }
            }

            FindlyCard {
                Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                    FindlyTextField(value = inviteCode, onValueChange = { inviteCode = it }, label = "Invite code")
                    FindlyTextField(value = displayName, onValueChange = { displayName = it }, label = "Your display name")
                    FindlyButton(
                        text = if (state.isAcceptingInvite) "Joining…" else "Join family",
                        enabled = !state.isAcceptingInvite && inviteCode.isNotBlank() && displayName.isNotBlank(),
                        onClick = { onAcceptInvite(inviteCode, displayName) },
                    )
                    state.acceptedFamily?.let { family ->
                        FindlyStatusChip(label = "Joined ${family.familyName} as ${family.role}", tone = FindlyStatusTone.Success)
                    }
                    state.acceptInviteError?.let { error ->
                        FindlyStatusChip(label = error, tone = FindlyStatusTone.Danger)
                    }
                }
            }
        }
    }
}

@Preview(name = "Invites — light", showBackground = true)
@Composable
private fun InvitesScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        InvitesScreen(
            state = InvitesUiState(createdInvite = CreatedInviteUi("7F3K9QRZ", "member", "2026-07-22T10:00:00Z")),
        )
    }
}

@Preview(name = "Invites — dark", showBackground = true)
@Composable
private fun InvitesScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        InvitesScreen(state = InvitesUiState())
    }
}
