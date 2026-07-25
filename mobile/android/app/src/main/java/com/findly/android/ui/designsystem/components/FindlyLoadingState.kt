package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A loading placeholder. Stateless, reads only [FindlyTheme] tokens (specs/003-android-client.md
 * §4.3).
 */
@Composable
fun FindlyLoadingState(
    modifier: Modifier = Modifier,
    message: String? = null,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(FindlyTheme.spacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        CircularProgressIndicator(color = FindlyTheme.colors.primary)
        if (message != null) {
            Text(
                text = message,
                color = FindlyTheme.colors.outline,
                style = FindlyTheme.typography.bodyMedium,
            )
        }
    }
}
