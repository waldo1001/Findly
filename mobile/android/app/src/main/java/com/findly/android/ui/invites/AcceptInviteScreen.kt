package com.findly.android.ui.invites

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import kotlinx.coroutines.launch

/**
 * The A36 accept-invite ("Join a family") screen (001-api-contract.md §3.4, specs/010-app-shell-
 * and-screen-ux.md §5.2) — reached from Onboarding's "I have an invite code", from
 * [com.findly.android.ui.groups.GroupsListScreen]'s "Manage family invites" (family-less state),
 * or from a `/f`/`findly://family-join` deep link with the code prefilled. Half of the retired
 * combined `InvitesScreen` (010 §6); [CreateInviteScreen] is the other.
 *
 * The smart code field is a **controlled** `TextField`: [code] is the backing, canonical (no
 * hyphen) state; its displayed `value` is [InviteCodeFieldFormatter.toDisplayForm], and
 * `onValueChange` runs the raw new text back through [InviteCodeFieldFormatter.filterToCode] —
 * so typing, backspacing, or pasting a hyphenated/lowercase/garbage-laced string all converge on
 * the same normalized value while the user types.
 *
 * **Paste is explicit-tap-only (MUST, 010 §5.2):** the clipboard is read only inside the "Paste
 * code" chip's own `onClick` — never on screen entry/composition — via [LocalClipboard]
 * `.getClipEntry()`, run through [InviteCodeClipboardExtractor]. A clipboard that doesn't hold a
 * recognizable code/link leaves the field untouched and surfaces a small inline notice rather
 * than silently doing nothing.
 *
 * **Display-name prefill (review-round fix):** when [prefillDisplayName] is blank — i.e. this
 * screen was *not* reached via Onboarding's profile-less display-name field — this route asks
 * [AcceptInviteViewModel.loadDisplayNameFallback] to resolve the caller's own profile
 * `displayName` from `GET /devices` (001 §4.2; see [AcceptInviteStateHolder.loadDisplayNameFallback]'s
 * doc for the wire-shape reasoning). [AcceptInviteScreen] seeds its display-name field from
 * [AcceptInviteUiState.displayNameFallback] only if the field is still blank when it arrives, so
 * it never clobbers anything the user already typed.
 */
@Composable
fun AcceptInviteRoute(
    viewModel: AcceptInviteViewModel,
    joinLinkHost: String,
    modifier: Modifier = Modifier,
    prefillCode: String = "",
    prefillDisplayName: String = "",
    onJoined: () -> Unit = {},
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        if (prefillDisplayName.isBlank()) viewModel.loadDisplayNameFallback()
    }

    AcceptInviteScreen(
        state = state,
        joinLinkHost = joinLinkHost,
        prefillCode = prefillCode,
        prefillDisplayName = prefillDisplayName,
        onJoin = viewModel::acceptInvite,
        onJoined = onJoined,
        modifier = modifier,
    )
}

@Composable
fun AcceptInviteScreen(
    state: AcceptInviteUiState,
    joinLinkHost: String,
    modifier: Modifier = Modifier,
    prefillCode: String = "",
    prefillDisplayName: String = "",
    onJoin: (inviteCode: String, displayName: String) -> Unit = { _, _ -> },
    onJoined: () -> Unit = {},
) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val coroutineScope = rememberCoroutineScope()
    var code by remember { mutableStateOf(InviteCodeFieldFormatter.filterToCode(prefillCode)) }
    var displayName by remember { mutableStateOf(prefillDisplayName) }
    var pasteNotice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(state.acceptedFamily) {
        if (state.acceptedFamily != null) onJoined()
    }

    // Review-round fix: seed the display-name field from the resolved fallback (001 §4.2's
    // GET /devices ownerDisplayName), but only while the field is still blank -- never overwrite
    // something the user already typed while the fallback was in flight.
    LaunchedEffect(state.displayNameFallback) {
        val fallback = state.displayNameFallback
        if (fallback != null && displayName.isBlank()) {
            displayName = fallback
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = "Join a family")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            FindlyCard {
                Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                    FindlyTextField(
                        value = InviteCodeFieldFormatter.toDisplayForm(code),
                        onValueChange = { code = InviteCodeFieldFormatter.filterToCode(it) },
                        label = "Invite code",
                        placeholder = "XXXX-XXXX",
                    )

                    // 010 §5.2 (MUST): explicit-tap-only -- the clipboard is read here, inside
                    // this onClick, and nowhere else on this screen.
                    FindlyButton(
                        text = "Paste code",
                        style = FindlyButtonStyle.Secondary,
                        compact = true,
                        onClick = {
                            coroutineScope.launch {
                                val clipboardText = clipboard.getClipEntry()
                                    ?.clipData
                                    ?.takeIf { it.itemCount > 0 }
                                    ?.getItemAt(0)
                                    ?.coerceToText(context)
                                    ?.toString()
                                val extracted = clipboardText?.let { InviteCodeClipboardExtractor.extract(it, joinLinkHost) }
                                if (extracted != null) {
                                    code = extracted
                                    pasteNotice = null
                                } else {
                                    pasteNotice = "Couldn't find an invite code on the clipboard"
                                }
                            }
                        },
                    )
                    pasteNotice?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Neutral) }

                    FindlyTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        label = "Your display name",
                    )

                    state.acceptInviteError?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }

                    FindlyButton(
                        text = if (state.isAcceptingInvite) "Joining…" else "Join family",
                        enabled = !state.isAcceptingInvite && code.isNotBlank() && displayName.isNotBlank(),
                        onClick = { onJoin(code, displayName) },
                    )
                }
            }
        }
    }
}

@Preview(name = "Accept invite — light", showBackground = true)
@Composable
private fun AcceptInviteScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        AcceptInviteScreen(
            state = AcceptInviteUiState(),
            joinLinkHost = "findly-join.example.net",
            prefillCode = "7F3K9QRZ",
        )
    }
}

@Preview(name = "Accept invite — dark (error)", showBackground = true)
@Composable
private fun AcceptInviteScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        AcceptInviteScreen(
            state = AcceptInviteUiState(acceptInviteError = "That invite code isn't valid."),
            joinLinkHost = "findly-join.example.net",
        )
    }
}
