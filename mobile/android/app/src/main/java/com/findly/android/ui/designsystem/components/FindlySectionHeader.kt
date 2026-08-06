package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A stateless section-title label (grouping a list — e.g. "Devices"/"Members" on the A2 settings
 * screen). Added in A2 so a screen never needs to reach for a bare Material3 `Text` composable
 * directly (specs/003-android-client.md §4.3: screens compose only `ui/designsystem` components).
 * Reads only [FindlyTheme] tokens. Geometry from design 2a
 * (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `FindlySectionHeader`): `labelSmall`
 * (uppercased — `TextStyle` has no text-transform, so [title] is uppercased here), muted color,
 * 4dp horizontal padding, 10dp below.
 */
@Composable
fun FindlySectionHeader(
    title: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = title.uppercase(),
        color = FindlyTheme.colors.subtleText,
        style = FindlyTheme.typography.labelSmall,
        modifier = modifier
            .fillMaxWidth()
            .padding(start = FindlyTheme.spacing.xs, end = FindlyTheme.spacing.xs, bottom = 10.dp),
    )
}
