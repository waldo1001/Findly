package com.findly.android.ui.groups

import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyCard
import com.findly.android.ui.designsystem.components.FindlyErrorState
import com.findly.android.ui.designsystem.components.FindlyListRow
import com.findly.android.ui.designsystem.components.FindlyLoadingState
import com.findly.android.ui.designsystem.components.FindlySectionHeader
import com.findly.android.ui.designsystem.components.FindlyStatusChip
import com.findly.android.ui.designsystem.components.FindlyStatusTone
import com.findly.android.ui.designsystem.components.FindlyTextField
import com.findly.android.ui.designsystem.components.FindlyTopBar
import java.time.Instant

/** The one owner action awaiting user confirmation (specs/003-android-client.md §12.2: "owner
 * controls behind confirm dialogs"). A single sealed type + one [AlertDialog] call site keeps the
 * five confirm flows (rename/extend/rotate/kick/delete) from needing five near-identical dialogs. */
private sealed class PendingGroupAction {
    data class Rename(val newName: String) : PendingGroupAction()
    data class Extend(val endsAtIso: String, val label: String) : PendingGroupAction()
    data object Rotate : PendingGroupAction()
    data class Kick(val userId: String, val displayName: String) : PendingGroupAction()
    data object Delete : PendingGroupAction()
}

/**
 * The A5 group-detail screen (001-api-contract.md §12.3-§12.5, §12.7-§12.9, specs/003-android-
 * client.md §12.2). Owner controls (rename, extend/end, rotate, kick, delete) run through
 * [AlertDialog] confirmations — one of the "un-migrated Material3 primitives" `FindlyTheme` already
 * themes correctly (specs/003 §4.3, same rationale as `HistoryScreen`'s `DatePickerDialog`
 * exception): a modal-overlay primitive with real platform behavior, not a styling primitive.
 *
 * On `GROUP_EXPIRED` ([GroupDetailUiState.Expired]) the screen shows a brief [Toast] — the same
 * visible notice [GroupMapScreen] gives on its identical `Expired` treatment (specs/003 §4.3's
 * documented exception; the `Expired` state's own message alone would render for at most one
 * composition frame before [onLeft] navigates away, effectively imperceptible) — and then bounces
 * back to the groups list via [onLeft] (specs/003 §12.2's "SHOULD bounce the user back to the
 * groups list with a notice"). After a successful leave/delete ([GroupDetailUiState.Content.left])
 * the same [onLeft] fires with no `Toast` — that's a deliberate, already-confirmed user action
 * (via an [AlertDialog] confirm or the plain "Leave group" button), not a surprise the user needs
 * to be told about.
 *
 * **A6 addition** (specs/007-public-join-links.md §1/§4, specs/003-android-client.md §12.3): the
 * share-sheet text now carries the canonical `https://{joinLinkHost}/g#{code}` link (007 §1: "the
 * https form is the canonical one for sharing and QR") instead of the `findly://` form — the
 * `findly://` scheme remains a fully supported deep link ([FindlyNavHost]), it's just no longer what
 * this screen puts in the share text (007 §1 assigns that role to the landing page's own "open the
 * app" affordance, W1 scope). A QR code of the same link renders below the share button, generated
 * entirely on-device via [GroupQrCodeGenerator] — no networked QR-image service is ever involved
 * (007 §4's hard requirement; see that object's doc for the full dependency justification).
 */
@Composable
fun GroupDetailRoute(
    viewModel: GroupDetailViewModel,
    joinLinkHost: String,
    modifier: Modifier = Modifier,
    onLeft: () -> Unit = {},
    onOpenMap: (groupId: String) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    LaunchedEffect(state) {
        val expired = state as? GroupDetailUiState.Expired
        if (expired != null) {
            Toast.makeText(context, expired.message, Toast.LENGTH_SHORT).show()
            onLeft()
            return@LaunchedEffect
        }
        if ((state as? GroupDetailUiState.Content)?.left == true) {
            onLeft()
        }
    }

    GroupDetailScreen(
        state = state,
        joinLinkHost = joinLinkHost,
        onRename = viewModel::rename,
        onExtend = viewModel::updateEndsAt,
        onRotateCode = viewModel::rotateCode,
        onKickMember = viewModel::kickMember,
        onDeleteGroup = viewModel::deleteGroup,
        onLeaveGroup = viewModel::leaveGroup,
        onOpenMap = onOpenMap,
        onRetry = viewModel::reload,
        modifier = modifier,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupDetailScreen(
    state: GroupDetailUiState,
    joinLinkHost: String,
    modifier: Modifier = Modifier,
    onRename: (String) -> Unit = {},
    onExtend: (String) -> Unit = {},
    onRotateCode: () -> Unit = {},
    onKickMember: (String) -> Unit = {},
    onDeleteGroup: () -> Unit = {},
    onLeaveGroup: () -> Unit = {},
    onOpenMap: (groupId: String) -> Unit = {},
    onRetry: () -> Unit = {},
) {
    val context = LocalContext.current
    var pendingAction by remember { mutableStateOf<PendingGroupAction?>(null) }
    var renameDraft by remember { mutableStateOf("") }

    Column(modifier = modifier.fillMaxSize()) {
        FindlyTopBar(title = if (state is GroupDetailUiState.Content) state.name else "Group")

        when (state) {
            is GroupDetailUiState.Loading -> FindlyLoadingState(message = "Loading group…")

            is GroupDetailUiState.Error -> FindlyErrorState(
                title = "Couldn't load this group",
                message = state.message,
                onRetry = onRetry,
            )

            // Transient — GroupDetailRoute's LaunchedEffect is about to navigate away.
            is GroupDetailUiState.Expired -> FindlyLoadingState(message = state.message)

            is GroupDetailUiState.Content -> {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(FindlyTheme.spacing.md),
                    verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
                ) {
                    FindlyCard {
                        Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                                FindlyStatusChip(label = state.state, tone = groupStateTone(state.state))
                                FindlyStatusChip(
                                    label = GroupCountdownFormatter.format(state.endsAt, Instant.now().toString()),
                                    tone = FindlyStatusTone.Neutral,
                                )
                            }
                            FindlyStatusChip(label = GroupPolicyCopy.forPolicy(state.expiryPolicy), tone = FindlyStatusTone.Neutral)
                            // 001 §12.10 — the group map only serves `active` groups (410
                            // GROUP_EXPIRED otherwise, 005 §2.3); hide the entry point rather than
                            // let the user land on an immediate bounce-back.
                            if (state.state == "active") {
                                FindlyButton(
                                    text = "View map",
                                    style = FindlyButtonStyle.Secondary,
                                    onClick = { onOpenMap(state.groupId) },
                                )
                            }
                        }
                    }

                    FindlyCard {
                        Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
                            if (state.code != null) {
                                val joinLink = remember(joinLinkHost, state.code) {
                                    GroupJoinLinkBuilder.buildHttpsLink(joinLinkHost, state.code)
                                }
                                FindlyStatusChip(label = "Code: ${state.code}", tone = FindlyStatusTone.Success)
                                FindlyButton(
                                    text = "Share code",
                                    style = FindlyButtonStyle.Secondary,
                                    onClick = {
                                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                            type = "text/plain"
                                            putExtra(
                                                Intent.EXTRA_TEXT,
                                                "Join my \"${state.name}\" group on Findly — " +
                                                    "code ${state.code}\n$joinLink",
                                            )
                                        }
                                        context.startActivity(Intent.createChooser(shareIntent, "Share group code"))
                                    },
                                )
                                // A6 (specs/007 §4): on-device QR of the exact share link above —
                                // no networked QR-image service (GroupQrCodeGenerator's doc has the
                                // full justification). Sized to fill the card's width rather than a
                                // hardcoded dp constant (specs/003 §4.1's token vocabulary has no
                                // token for "QR code edge length"; aspectRatio(1f) keeps it square
                                // at whatever width the layout gives it).
                                Image(
                                    bitmap = remember(joinLink) { GroupQrCodeGenerator.toBitmap(joinLink).asImageBitmap() },
                                    contentDescription = "QR code to join \"${state.name}\" — $joinLink",
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(1f)
                                        .padding(top = FindlyTheme.spacing.sm),
                                    filterQuality = FilterQuality.None,
                                )
                            } else {
                                FindlyStatusChip(label = "Code no longer available", tone = FindlyStatusTone.Neutral)
                            }
                        }
                    }

                    state.mutationError?.let { FindlyStatusChip(label = it, tone = FindlyStatusTone.Danger) }

                    if (state.isOwner) {
                        FindlySectionHeader(title = "Owner controls")
                        FindlyCard {
                            Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                                FindlyTextField(value = renameDraft, onValueChange = { renameDraft = it }, label = "Rename group")
                                Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                                    FindlyButton(
                                        text = "Rename",
                                        enabled = !state.isMutating && renameDraft.isNotBlank(),
                                        style = FindlyButtonStyle.Secondary,
                                        onClick = { pendingAction = PendingGroupAction.Rename(renameDraft) },
                                    )
                                    FindlyButton(
                                        text = "Rotate code",
                                        enabled = !state.isMutating,
                                        style = FindlyButtonStyle.Secondary,
                                        onClick = { pendingAction = PendingGroupAction.Rotate },
                                    )
                                }
                                FindlyButton(
                                    text = "End group now",
                                    enabled = !state.isMutating,
                                    style = FindlyButtonStyle.Secondary,
                                    onClick = {
                                        // 001 §12.4: endsAt MUST be > now, and "endsAt <= now + 5min"
                                        // is the server's "end it now" convenience — 60s ahead is
                                        // safely inside that window and can't race negative against
                                        // the server's own clock (unlike sending exactly `now`).
                                        pendingAction = PendingGroupAction.Extend(
                                            endsAtIso = Instant.now().plusSeconds(60).toString(),
                                            label = "end this group now",
                                        )
                                    },
                                )
                                FindlyButton(
                                    text = "Delete group",
                                    enabled = !state.isMutating,
                                    style = FindlyButtonStyle.Secondary,
                                    onClick = { pendingAction = PendingGroupAction.Delete },
                                )
                            }
                        }
                    } else {
                        FindlyButton(
                            text = "Leave group",
                            enabled = !state.isMutating,
                            style = FindlyButtonStyle.Secondary,
                            onClick = onLeaveGroup,
                        )
                    }
                }

                val members = state.members
                if (members == null) {
                    FindlyStatusChip(
                        label = "Member list hidden while this group is ending",
                        tone = FindlyStatusTone.Neutral,
                        modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md),
                    )
                } else {
                    FindlySectionHeader(title = "Members", modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md))
                    LazyColumn(
                        modifier = Modifier.padding(horizontal = FindlyTheme.spacing.md),
                        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
                    ) {
                        items(members, key = { it.userId }) { member ->
                            val kickAction: (@Composable RowScope.() -> Unit)? = if (state.isOwner && member.role != "owner") {
                                {
                                    FindlyButton(
                                        text = "Kick",
                                        style = FindlyButtonStyle.Secondary,
                                        onClick = { pendingAction = PendingGroupAction.Kick(member.userId, member.displayName) },
                                    )
                                }
                            } else {
                                null
                            }
                            FindlyListRow(
                                title = member.displayName,
                                subtitle = member.role,
                                trailing = kickAction,
                            )
                        }
                    }
                }
            }
        }
    }

    val action = pendingAction
    if (action != null) {
        GroupActionConfirmDialog(
            action = action,
            onConfirm = {
                when (action) {
                    is PendingGroupAction.Rename -> onRename(action.newName)
                    is PendingGroupAction.Extend -> onExtend(action.endsAtIso)
                    is PendingGroupAction.Rotate -> onRotateCode()
                    is PendingGroupAction.Kick -> onKickMember(action.userId)
                    is PendingGroupAction.Delete -> onDeleteGroup()
                }
                pendingAction = null
            },
            onDismiss = { pendingAction = null },
        )
    }
}

@Composable
private fun GroupActionConfirmDialog(
    action: PendingGroupAction,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val message = when (action) {
        is PendingGroupAction.Rename -> "Rename this group to \"${action.newName}\"?"
        is PendingGroupAction.Extend -> "Are you sure you want to ${action.label}?"
        is PendingGroupAction.Rotate -> "Rotate the join code? The old code will stop working immediately."
        is PendingGroupAction.Kick -> "Remove ${action.displayName} from this group?"
        is PendingGroupAction.Delete -> "Delete this group? Everything — members, positions, the join code — is removed immediately and cannot be undone."
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        text = { Text(message) },
        confirmButton = { FindlyButton(text = "Confirm", onClick = onConfirm) },
        dismissButton = { FindlyButton(text = "Cancel", onClick = onDismiss, style = FindlyButtonStyle.Secondary) },
    )
}

private fun groupStateTone(state: String): FindlyStatusTone = when (state) {
    "active" -> FindlyStatusTone.Success
    "ended" -> FindlyStatusTone.Warning
    else -> FindlyStatusTone.Neutral
}

@Preview(name = "Group detail — light (owner)", showBackground = true)
@Composable
private fun GroupDetailScreenLightPreview() {
    FindlyTheme(darkTheme = false) {
        GroupDetailScreen(
            state = GroupDetailUiState.Content(
                groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz",
                name = "Festival crew",
                endsAt = "2026-08-02T22:00:00Z",
                expiryPolicy = "delete",
                state = "active",
                role = "owner",
                memberCount = 2,
                code = "7F3K9QRZ",
                createdAt = "2026-07-21T10:00:00Z",
                members = listOf(
                    GroupMemberUi("u1", "Eric", "owner", "2026-07-21T10:00:00Z"),
                    GroupMemberUi("u9", "Noor", "member", "2026-07-21T10:05:00Z"),
                ),
            ),
            joinLinkHost = "CHANGE-ME.azurestaticapps.net",
        )
    }
}

@Preview(name = "Group detail — dark (member, roster hidden)", showBackground = true)
@Composable
private fun GroupDetailScreenDarkPreview() {
    FindlyTheme(darkTheme = true) {
        GroupDetailScreen(
            state = GroupDetailUiState.Content(
                groupId = "grp_9J2Kq7Lm3NpR5sTvWxYz",
                name = "Festival crew",
                endsAt = "2026-07-21T22:00:00Z",
                expiryPolicy = "grace",
                state = "ended",
                role = "member",
                memberCount = 2,
                code = null,
                createdAt = "2026-07-21T10:00:00Z",
                members = null,
            ),
            joinLinkHost = "CHANGE-ME.azurestaticapps.net",
        )
    }
}
