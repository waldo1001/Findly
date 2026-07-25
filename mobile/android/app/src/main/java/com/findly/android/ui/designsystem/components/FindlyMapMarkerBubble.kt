package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A map-marker label bubble (a family member's name pin on the live map, A2). Fresh (`isStale =
 * false`) uses the `primary` token; stale uses `outline`, so staleness reads identically across
 * both apps/themes without any per-screen color logic (001-api-contract.md §5.2's `isStale`
 * rule). Stateless — reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 */
@Composable
fun FindlyMapMarkerBubble(
    label: String,
    isStale: Boolean,
    modifier: Modifier = Modifier,
) {
    val tint = if (isStale) FindlyTheme.colors.outline else FindlyTheme.colors.primary

    Text(
        text = label,
        color = FindlyTheme.colors.surface,
        style = FindlyTheme.typography.labelSmall,
        modifier = modifier
            .clip(RoundedCornerShape(FindlyTheme.corner.pill))
            .background(tint)
            .border(width = FindlyTheme.elevation.level1, color = FindlyTheme.colors.surface, shape = RoundedCornerShape(FindlyTheme.corner.pill))
            .padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.xs),
    )
}
