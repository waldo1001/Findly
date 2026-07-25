package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
 * A stateless top app bar. Reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 */
@Composable
fun FindlyTopBar(
    title: String,
    modifier: Modifier = Modifier,
    navigationIcon: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(FindlyTheme.colors.surface)
            .padding(horizontal = FindlyTheme.spacing.md, vertical = FindlyTheme.spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        navigationIcon?.invoke()

        Text(
            text = title,
            color = FindlyTheme.colors.onSurface,
            style = FindlyTheme.typography.titleLarge,
            modifier = Modifier.weight(1f),
        )

        actions()
    }
}
