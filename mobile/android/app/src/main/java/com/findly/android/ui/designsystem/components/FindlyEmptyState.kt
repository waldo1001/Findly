package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * "Nothing here yet" placeholder (e.g. no devices registered, no history in range). Stateless,
 * reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 */
@Composable
fun FindlyEmptyState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(FindlyTheme.spacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        Text(
            text = title,
            color = FindlyTheme.colors.onSurface,
            style = FindlyTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        Text(
            text = message,
            color = FindlyTheme.colors.outline,
            style = FindlyTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )
    }
}
