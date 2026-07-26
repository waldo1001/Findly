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
 * Every design-system component rendered together — a visual regression aid so a future design
 * swap (docs/design-prompt.md, per docs/implementation-handoff.md's Mobile H1-waiver note) can
 * be checked at a glance in both themes. Not a screen; not wired into navigation.
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

        FindlyButton(text = "Primary action", onClick = {})
        FindlyButton(text = "Secondary action", onClick = {}, style = FindlyButtonStyle.Secondary)
        FindlyButton(text = "Disabled", onClick = {}, enabled = false)

        FindlyCard {
            Text(
                text = "Card content",
                color = FindlyTheme.colors.onSurface,
                style = FindlyTheme.typography.bodyLarge,
            )
        }

        FindlyListRow(title = "Noor", subtitle = "Last seen 2 min ago")

        Column(verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.xs)) {
            FindlyStatusChip(label = "Registered", tone = FindlyStatusTone.Success)
            FindlyStatusChip(label = "Stale", tone = FindlyStatusTone.Warning)
            FindlyStatusChip(label = "Error", tone = FindlyStatusTone.Danger)
            FindlyStatusChip(label = "Paused", tone = FindlyStatusTone.Neutral)
        }

        FindlyMapMarkerBubble(label = "Eric", state = FindlyMapMarkerState.Online)
        FindlyMapMarkerBubble(label = "Noor", state = FindlyMapMarkerState.Stale)
        FindlyMapMarkerBubble(label = "?", state = FindlyMapMarkerState.NoLocation)

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

        FindlySwitchRow(title = "Tracking enabled", checked = true, onCheckedChange = {})
        FindlySwitchRow(title = "Notify on enter", checked = false, onCheckedChange = {}, subtitle = "Geofence: Home")

        FindlyEmptyState(title = "No devices yet", message = "Register a device to see it here.")
        FindlyLoadingState(message = "Loading…")
        FindlyErrorState(title = "Something went wrong", message = "Couldn't reach the server.", onRetry = {})
    }
}

@Preview(name = "Component gallery — light", showBackground = true)
@Composable
private fun ComponentGalleryLightPreview() {
    FindlyTheme(darkTheme = false) {
        ComponentGallery()
    }
}

@Preview(name = "Component gallery — dark", showBackground = true)
@Composable
private fun ComponentGalleryDarkPreview() {
    FindlyTheme(darkTheme = true) {
        ComponentGallery()
    }
}
