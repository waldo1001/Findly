package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.findly.android.location.PermissionBanner
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * specs/009-device-runtime.md §7 — the persistent, dismissible-per-session degraded-state banner.
 *
 * Denial is never fatal here: the family map still works and other members' locations are
 * unaffected; only *this* device stops contributing. That is exactly why the banner is required —
 * without it the app looks like it is working while quietly reporting nothing, the worst outcome
 * for a product whose whole promise is "you can see where everyone is".
 *
 * Stateless like every other component in this package: what to show is decided by
 * [com.findly.android.location.PermissionFlowPolicy.banner], never here. Copy mirrors iOS's
 * `PermissionBannerView`.
 */
@Composable
fun FindlyPermissionBanner(
    banner: PermissionBanner,
    onOpenSettings: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (banner == PermissionBanner.NONE) return

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(FindlyTheme.colors.surfaceVariant),
    ) {
        // A severity stripe rather than a coloured background: it reads at a glance without making
        // the whole banner shout, and distinguishes the two states by form as well as by wording.
        Column(
            modifier = Modifier
                .width(4.dp)
                .height(IntrinsicBannerHeight)
                .background(
                    if (banner == PermissionBanner.CANNOT_REPORT) {
                        FindlyTheme.colors.danger
                    } else {
                        FindlyTheme.colors.primary
                    },
                ),
        ) {}

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(FindlyTheme.spacing.md),
            verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm)) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs),
                ) {
                    Text(
                        text = titleFor(banner),
                        style = FindlyTheme.typography.titleMedium,
                        color = FindlyTheme.colors.onSurface,
                    )
                    Text(
                        text = messageFor(banner),
                        style = FindlyTheme.typography.bodyMedium,
                        color = FindlyTheme.colors.onSurface.copy(alpha = 0.75f),
                    )
                }
                Text(
                    text = "✕",
                    style = FindlyTheme.typography.bodyLarge,
                    // A28 security review (Major 1): was `onSurface.copy(alpha = 0.6f)`, an
                    // ad-hoc translucent foreground the design-token contrast suite structurally
                    // couldn't see — measured, light blends to ~4.43:1 on this banner's
                    // `surfaceVariant` fill, below the 4.5:1 floor for 17sp/400 body text (dark
                    // happened to pass at ~5.87:1). `subtleText` is the token that exists for
                    // exactly this "muted body text" job (5.79:1 light / 6.49:1 dark on
                    // `surfaceVariant`) — using it removes both the AA failure and the ad-hoc
                    // alpha in one change (see ColorTokenContrastTest.kt's pinned regression test
                    // for the old pattern, and the declared "FindlyPermissionBanner dismiss glyph
                    // (subtleText) on surfaceVariant" pairing for this one).
                    color = FindlyTheme.colors.subtleText,
                    modifier = Modifier
                        .clickable(onClick = onDismiss)
                        .padding(FindlyTheme.spacing.xs)
                        .semantics { contentDescription = "Dismiss" },
                )
            }

            // 009 §7 requires "a route into system settings" — a banner that only states the
            // problem leaves the user to find Settings themselves, which most will not.
            FindlyButton(
                text = "Open settings",
                style = FindlyButtonStyle.Secondary,
                onClick = onOpenSettings,
            )
        }
    }
}

/** The stripe spans the banner; a fixed floor keeps it visible while the text wraps. */
private val IntrinsicBannerHeight = 132.dp

private fun titleFor(banner: PermissionBanner) = when (banner) {
    PermissionBanner.CANNOT_REPORT -> "Your location isn't being shared"
    PermissionBanner.FOREGROUND_ONLY -> "Only sharing while Findly is open"
    PermissionBanner.NONE -> ""
}

/**
 * Says what is happening, what the consequence is, and how to fix it — no apology, no blame for
 * having refused. Refusing is a legitimate choice; the app's job is to be honest that it changes
 * what the family sees.
 */
private fun messageFor(banner: PermissionBanner) = when (banner) {
    PermissionBanner.CANNOT_REPORT ->
        "Findly can't access your location, so your family can't see where you are. " +
            "You can still see everyone else. Turn on location access to start sharing again."
    PermissionBanner.FOREGROUND_ONLY ->
        "Your location updates only while Findly is open on screen. " +
            "Allow location access all the time to keep your family up to date in the background."
    PermissionBanner.NONE -> ""
}
