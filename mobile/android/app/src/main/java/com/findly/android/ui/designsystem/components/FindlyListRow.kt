package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A stateless single-line-or-two list row (roster entries, device rows, history entries, …).
 * Reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 */
@Composable
fun FindlyListRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val rowModifier = if (onClick != null) {
        modifier.fillMaxWidth().clickable(onClick = onClick)
    } else {
        modifier.fillMaxWidth()
    }

    Row(
        modifier = rowModifier
            .background(FindlyTheme.colors.surface)
            .padding(horizontal = FindlyTheme.spacing.md, vertical = FindlyTheme.spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        leading?.invoke()

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                color = FindlyTheme.colors.onSurface,
                style = FindlyTheme.typography.bodyLarge,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    color = FindlyTheme.colors.outline,
                    style = FindlyTheme.typography.bodyMedium,
                )
            }
        }

        trailing?.invoke(this)
    }
}
