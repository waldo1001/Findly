package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * Every design-system component — and every state design 2a "Ember / Dusk"
 * (design/findly-design-system/2a-ember-dusk/HANDOFF.md) calls out — rendered together, a visual
 * regression aid so a future design swap can be checked at a glance in both themes. Not a screen;
 * not wired into navigation.
 */
@Composable
private fun ComponentGallery(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(FindlyTheme.colors.surface)
            .padding(FindlyTheme.spacing.md),
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
    ) {
        FindlyTopBar(title = "Findly")

        FindlySectionHeader(title = "Buttons")
        FindlyButton(text = "Primary action", onClick = {})
        FindlyButton(text = "Primary disabled", onClick = {}, enabled = false)
        FindlyButton(text = "Secondary action", onClick = {}, style = FindlyButtonStyle.Secondary)
        FindlyButton(text = "Secondary disabled", onClick = {}, style = FindlyButtonStyle.Secondary, enabled = false)
        FindlyButton(text = "Destructive action", onClick = {}, style = FindlyButtonStyle.Destructive)
        FindlyButton(text = "Compact (inline)", onClick = {}, compact = true)

        FindlySectionHeader(title = "Card")
        FindlyCard {
            Text(
                text = "Card content",
                color = FindlyTheme.colors.onSurface,
                style = FindlyTheme.typography.bodyLarge,
            )
        }

        FindlySectionHeader(title = "List rows")
        FindlyListRow(title = "Noor", subtitle = "Last seen 2 min ago")
        FindlyListRow(title = "Sam", subtitle = "Oak Street · 24 min ago", onClick = {})
        FindlyListRow(title = "Dad", subtitle = "Sharing paused", enabled = false)

        FindlySectionHeader(title = "Status chips")
        Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
            // Device-status usage: glyph opted in (matches HomeScreen/MapScreen/GroupMapScreen's
            // real call sites — short status words, matching HANDOFF's own model).
            FindlyStatusChip(label = "ONLINE", tone = FindlyStatusTone.Success, showStatusGlyph = true)
            FindlyStatusChip(label = "STALE", tone = FindlyStatusTone.Warning, showStatusGlyph = true)
            FindlyStatusChip(label = "PAUSED", tone = FindlyStatusTone.Neutral, showStatusGlyph = true)
            FindlyStatusChip(label = "ALERT", tone = FindlyStatusTone.Danger, showStatusGlyph = true)
            // General-purpose badge usage (the default): plain label, no glyph — e.g.
            // GroupDetailScreen's "Code: ABC123", a validation-error chip, or LocateScreen's
            // prose status messages ("Waiting for a response…") where the glyph rule doesn't
            // apply (see FindlyStatusChip's doc comment).
            FindlyStatusChip(label = "Code: ABC123", tone = FindlyStatusTone.Success)
        }

        FindlySectionHeader(title = "Map marker bubbles")
        FindlyMapMarkerBubble(label = "Noor", state = FindlyMapMarkerState.Online)
        FindlyMapMarkerBubble(label = "Sam", state = FindlyMapMarkerState.Stale, staleAgeText = "24m")
        FindlyMapMarkerBubble(label = "?", state = FindlyMapMarkerState.NoLocation)

        FindlySectionHeader(title = "Text fields")
        FindlyTextField(
            value = "Home",
            onValueChange = {},
            label = "Name",
            placeholder = "e.g. Home",
        )
        FindlyTextField(
            value = "",
            onValueChange = {},
            label = "Radius (m)",
            isError = true,
            supportingText = "Must be between 100 and 5000",
        )
        FindlyTextField(
            value = "Locked",
            onValueChange = {},
            label = "Disabled field",
            enabled = false,
        )

        FindlySectionHeader(title = "Switch rows")
        FindlySwitchRow(title = "Tracking enabled", checked = true, onCheckedChange = {})
        FindlySwitchRow(title = "Notify on enter", checked = false, onCheckedChange = {}, subtitle = "Geofence: Home")
        FindlySwitchRow(title = "Disabled", checked = true, onCheckedChange = {}, enabled = false)

        FindlySectionHeader(title = "Nav drawer (010 §1.2)")
        FindlyNavDrawerMenuButton(onClick = {})

        FindlySectionHeader(title = "Empty / loading / error states")
        FindlyEmptyState(
            title = "No devices yet",
            message = "Register a device to see it here.",
            actionLabel = "Add a device",
            onAction = {},
        )
        FindlyLoadingState(message = "Loading…")
        FindlyErrorState(title = "Couldn't reach Sam's Pixel", message = "It may be off or out of signal.", onRetry = {})
    }
}

@Preview(name = "Component gallery — light", showBackground = true, heightDp = 3200)
@Composable
private fun ComponentGalleryLightPreview() {
    FindlyTheme(darkTheme = false) {
        ComponentGallery()
    }
}

@Preview(name = "Component gallery — dark", showBackground = true, heightDp = 3200)
@Composable
private fun ComponentGalleryDarkPreview() {
    FindlyTheme(darkTheme = true) {
        ComponentGallery()
    }
}
