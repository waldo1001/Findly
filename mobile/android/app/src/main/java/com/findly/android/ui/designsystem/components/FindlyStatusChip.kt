package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import com.findly.android.ui.designsystem.FindlyTheme

/** Semantic tone for a status chip — maps 1:1 onto a color token, never a raw color. */
enum class FindlyStatusTone { Success, Warning, Danger, Neutral }

/**
 * A small pill-shaped status indicator (device registered / paused / stale / error, …). Reads
 * only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 */
@Composable
fun FindlyStatusChip(
    label: String,
    tone: FindlyStatusTone,
    modifier: Modifier = Modifier,
) {
    val background: Color
    val onBackground: Color
    when (tone) {
        FindlyStatusTone.Success -> {
            background = FindlyTheme.colors.success
            onBackground = FindlyTheme.colors.onPrimary
        }
        FindlyStatusTone.Warning -> {
            background = FindlyTheme.colors.warning
            onBackground = FindlyTheme.colors.onSurface
        }
        FindlyStatusTone.Danger -> {
            background = FindlyTheme.colors.danger
            onBackground = FindlyTheme.colors.onDanger
        }
        FindlyStatusTone.Neutral -> {
            background = FindlyTheme.colors.surfaceVariant
            onBackground = FindlyTheme.colors.onSurface
        }
    }

    Text(
        text = label,
        color = onBackground,
        style = FindlyTheme.typography.labelSmall,
        modifier = modifier
            .clip(RoundedCornerShape(FindlyTheme.corner.pill))
            .background(background)
            .padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.xs),
    )
}
