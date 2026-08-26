package com.findly.android.ui.invites

import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import android.content.ClipData
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.joincode.JoinCodeAlphabet
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyCodeDisplay
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import com.findly.android.ui.groups.GroupQrCodeGenerator
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The A36 create-invite screen (001-api-contract.md §3.3, specs/010-app-shell-and-screen-ux.md
 * §5.1) — parent-only, reached from the drawer's "Invite someone" item. Half of the retired
 * combined `InvitesScreen` (010 §6); [AcceptInviteScreen] is the other. Renders the initial
 * create form until [state]`.createdInvite` exists, then the §5.1 success view: large copyable
 * code, expiry from the server's `expiresAt`, an on-device QR of the 007 §1 family-invite link
 * (reusing [GroupQrCodeGenerator] — 010 §5.1: "reuse the existing group QR components"), a share
 * button carrying the exact 007 §4 template, the handoff's footnote verbatim, and "Create
 * another".
 */
@Composable
fun CreateInviteRoute(
    viewModel: CreateInviteViewModel,
    joinLinkHost: String,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsState()
    CreateInviteScreen(
        state = state,
        joinLinkHost = joinLinkHost,
        onCreateInvite = viewModel::createInvite,
        onCreateAnother = viewModel::reset,
        modifier = modifier,
    )
}

@Composable
fun CreateInviteScreen(
    state: CreateInviteUiState,
    joinLinkHost: String,
    modifier: Modifier = Modifier,
    onCreateInvite: (role: String, emailHint: String?) -> Unit = { _, _ -> },
    onCreateAnother: () -> Unit = {},
) {
    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Invite someone")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.lg),
        ) {
            val createdInvite = state.createdInvite
            if (createdInvite == null) {
                CreateInviteForm(
                    isCreating = state.isCreatingInvite,
                    error = state.createInviteError,
                    onCreateInvite = onCreateInvite,
                )
            } else {
                CreateInviteSuccess(
                    invite = createdInvite,
                    joinLinkHost = joinLinkHost,
                    onCreateAnother = onCreateAnother,
                )
            }
        }
    }
}

@Composable
private fun CreateInviteForm(
    isCreating: Boolean,
    error: String?,
    onCreateInvite: (role: String, emailHint: String?) -> Unit,
) {
    var selectedRole by remember { mutableStateOf("member") }
    var emailHint by remember { mutableStateOf("") }

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
                text = if (isCreating) "Creating…" else "Create invite",
                enabled = !isCreating,
                onClick = { onCreateInvite(selectedRole, emailHint.ifBlank { null }) },
            )
            error?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }
        }
    }
}

/** specs/010-app-shell-and-screen-ux.md §5.1's six-part success view. */
@Composable
private fun CreateInviteSuccess(
    invite: CreatedInviteUi,
    joinLinkHost: String,
    onCreateAnother: () -> Unit,
) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val coroutineScope = rememberCoroutineScope()
    var justCopied by remember { mutableStateOf(false) }

    val sanitizedCode = remember(invite.inviteCode) {
        requireNotNull(FamilyInviteCodeSanitizer.sanitize(invite.inviteCode)) {
            "server-issued inviteCode must already be a valid 001 §1.4 code"
        }
    }
    val displayCode = remember(sanitizedCode) { JoinCodeAlphabet.toDisplayForm(sanitizedCode) }
    val joinLink = remember(joinLinkHost, sanitizedCode) {
        FamilyInviteLinkBuilder.buildHttpsLink(joinLinkHost, sanitizedCode)
    }

    LaunchedEffect(justCopied) {
        if (justCopied) {
            delay(2000)
            justCopied = false
        }
    }

    FindlyCard {
        Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md)) {
            // 1) The code, large and copyable: titleLarge-class size, tabular figures,
            //    letter-spaced, hyphenated display form (010 §5.1) -- rendered by the
            //    FindlyCodeDisplay design-system component (review-round addition) rather than a
            //    screen-level TextStyle literal, per FindlyCodeDisplay's own doc.
            FindlyCodeDisplay(code = displayCode)
            Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                FindlyButton(
                    text = if (justCopied) "Copied" else "Copy code",
                    style = FindlyButtonStyle.Secondary,
                    compact = true,
                    onClick = {
                        coroutineScope.launch {
                            clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Invite code", displayCode)))
                        }
                        justCopied = true
                    },
                )
            }

            // 2) Expiry, computed from the server's expiresAt -- never a hardcoded 72.
            Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                Text(
                    text = "It works once and expires in 72 hours.",
                    color = FindlyTheme.colors.subtleText,
                    style = FindlyTheme.typography.bodyMedium,
                )
                Text(
                    text = "Expires ${InviteExpiryFormatter.formatExpiresAt(invite.expiresAt)}",
                    color = FindlyTheme.colors.subtleText,
                    style = FindlyTheme.typography.bodyMedium,
                )
            }

            // 3) An on-device QR of the 007 §1 family-invite link -- reuses the group QR
            //    generator (GroupQrCodeGenerator's doc has the full "why on-device" reasoning);
            //    no networked QR-image service is ever involved.
            Image(
                bitmap = remember(joinLink) { GroupQrCodeGenerator.toBitmap(joinLink).asImageBitmap() },
                contentDescription = "QR code to join the family -- $joinLink",
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f),
                filterQuality = FilterQuality.None,
            )

            // 4) Share invite -> OS share sheet, exact 007 §4 template.
            FindlyButton(
                text = "Share invite",
                onClick = {
                    val shareText = FamilyInviteShareTextBuilder.build(joinLinkHost, sanitizedCode)
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, shareText)
                    }
                    context.startActivity(Intent.createChooser(shareIntent, "Share invite"))
                },
            )

            // 5) The handoff's footnote, verbatim.
            Text(
                text = "Anyone with this code can see your family's locations, so send it directly to the person joining.",
                color = FindlyTheme.colors.subtleText,
                style = FindlyTheme.typography.bodyMedium,
            )

            // 6) Create another, without leaving the screen.
            FindlyButton(text = "Create another", style = FindlyButtonStyle.Secondary, onClick = onCreateAnother)
        }
    }
}

@Preview(name = "Create invite — form, light", showBackground = true)
@Composable
private fun CreateInviteScreenFormPreview() {
    FindlyTheme(darkTheme = false) {
        CreateInviteScreen(state = CreateInviteUiState(), joinLinkHost = "findly-join.example.net")
    }
}

@Preview(name = "Create invite — success, dark", showBackground = true)
@Composable
private fun CreateInviteScreenSuccessPreview() {
    FindlyTheme(darkTheme = true) {
        CreateInviteScreen(
            state = CreateInviteUiState(
                createdInvite = CreatedInviteUi("7F3K9QRZ", "member", "2026-07-22T10:00:00Z"),
            ),
            joinLinkHost = "findly-join.example.net",
        )
    }
}
