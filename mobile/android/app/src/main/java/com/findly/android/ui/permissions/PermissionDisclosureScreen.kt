package com.findly.android.ui.permissions

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.findly.android.location.PermissionDisclosureKind
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.components.FindlyButton
import com.findly.android.ui.designsystem.components.FindlyButtonStyle
import com.findly.android.ui.designsystem.components.FindlyTopBar

/**
 * specs/009-device-runtime.md §7 — the prominent disclosure, shown **before** the OS permission
 * prompt.
 *
 * A Play policy requirement, not a nicety: background-location review expects an in-app screen
 * stating what is collected, why, and who sees it, *ahead* of the system dialog, and asks for a
 * recording of that flow. It is also the honest ordering — the system dialog is a yes/no with no
 * room to explain why a family locator wants background location.
 *
 * Two kinds, deliberately separate screens (003 §11.2): Android 11+ forbids bundling the foreground
 * and background asks in one dialog, so each gets its own explanation immediately before its own
 * prompt. Copy is kept in step with iOS's `PermissionDisclosureScreen` — the disclosure is what
 * both stores assess, so the two clients saying different things would be a real inconsistency.
 *
 * Stateless: acknowledgement is written by the caller through
 * [com.findly.android.location.PermissionDisclosureStore], and what to show next is decided by
 * [com.findly.android.location.PermissionFlowPolicy].
 */
@Composable
fun PermissionDisclosureScreen(
    kind: PermissionDisclosureKind,
    onContinue: () -> Unit,
    onNotNow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(FindlyTheme.colors.surfaceVariant),
    ) {
        FindlyTopBar(title = titleFor(kind))

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
        ) {
            Text(
                text = headlineFor(kind),
                style = FindlyTheme.typography.titleLarge,
                color = FindlyTheme.colors.onSurface,
            )

            Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                pointsFor(kind).forEach { point ->
                    Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                        // A plain bullet, not an icon set: these are three sentences of disclosure,
                        // and decorating them would undercut the tone.
                        Text(
                            text = "•",
                            style = FindlyTheme.typography.bodyLarge,
                            color = FindlyTheme.colors.primary,
                        )
                        Text(
                            text = point,
                            style = FindlyTheme.typography.bodyMedium,
                            color = FindlyTheme.colors.onSurface,
                        )
                    }
                }
            }

            Text(
                text = closingFor(kind),
                style = FindlyTheme.typography.bodyMedium,
                color = FindlyTheme.colors.onSurface.copy(alpha = 0.75f),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(FindlyTheme.colors.surface)
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            FindlyButton(text = continueTitleFor(kind), onClick = onContinue)
            // "Not now" must be a real, equally reachable choice — a disclosure that only offers
            // agreement is a dark pattern, and reviewers do notice. Declining is non-fatal: the
            // family map still works, this device just doesn't report.
            FindlyButton(text = "Not now", style = FindlyButtonStyle.Secondary, onClick = onNotNow)
        }
    }
}

private fun titleFor(kind: PermissionDisclosureKind) = when (kind) {
    PermissionDisclosureKind.FOREGROUND -> "Sharing your location"
    PermissionDisclosureKind.BACKGROUND -> "Sharing in the background"
}

private fun headlineFor(kind: PermissionDisclosureKind) = when (kind) {
    PermissionDisclosureKind.FOREGROUND -> "Findly shares your location with your family"
    PermissionDisclosureKind.BACKGROUND -> "Keep sharing when Findly isn't open"
}

/**
 * The three things a disclosure has to answer: what is collected, what it is used for, and who can
 * see it. Written plainly — a family member reads this, not a lawyer.
 */
private fun pointsFor(kind: PermissionDisclosureKind) = when (kind) {
    PermissionDisclosureKind.FOREGROUND -> listOf(
        "Findly collects this device's location so it can appear on your family's map.",
        "Only people in the families and groups you have joined can see it. It is never sold or shared with anyone else.",
        "You can pause sharing at any time in Settings, and delete your history and account from inside the app.",
    )
    PermissionDisclosureKind.BACKGROUND -> listOf(
        "To keep the map up to date, Findly needs to collect your location even when the app is closed or not in use.",
        "This is what lets your family see where you are without you opening the app, and what makes arrival and departure alerts for places like home or school work.",
        "Background updates follow the interval you choose in Settings, and stop entirely when you pause sharing.",
    )
}

private fun closingFor(kind: PermissionDisclosureKind) = when (kind) {
    PermissionDisclosureKind.FOREGROUND ->
        "On the next screen, Android will ask for permission. Choosing \"Don't allow\" keeps everything else working — you just won't appear on the map."
    PermissionDisclosureKind.BACKGROUND ->
        "On the next screen, Android will ask you to choose \"Allow all the time\". You can change this at any time in Android Settings."
}

private fun continueTitleFor(kind: PermissionDisclosureKind) = when (kind) {
    PermissionDisclosureKind.FOREGROUND -> "Continue"
    PermissionDisclosureKind.BACKGROUND -> "Allow in the background"
}
