package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A stateless section-title label (grouping a list — e.g. "Devices"/"Members" on the A2 settings
 * screen). Added in A2 so a screen never needs to reach for a bare Material3 `Text` composable
 * directly (specs/003-android-client.md §4.3: screens compose only `ui/designsystem` components).
 * Reads only [FindlyTheme] tokens.
 */
@Composable
fun FindlySectionHeader(
    title: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = title,
        color = FindlyTheme.colors.onSurface,
        style = FindlyTheme.typography.titleMedium,
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = FindlyTheme.spacing.xs),
    )
}
