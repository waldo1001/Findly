package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A loading placeholder. Stateless, reads only [FindlyTheme] tokens (specs/003-android-client.md
 * §4.3). Design 2a (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `EmptyState /
 * LoadingState / ErrorState`): radius `lg`, `surfaceVariant` fill, 22dp padding; the loading
 * indicator itself is a 6dp determinate-or-indeterminate bar in `primary` on a `surface` track
 * (an indeterminate `LinearProgressIndicator` here — this component has no notion of a fill
 * fraction to be determinate against).
 */
@Composable
fun FindlyLoadingState(
    modifier: Modifier = Modifier,
    message: String? = null,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(FindlyTheme.corner.lg))
            .background(FindlyTheme.colors.surfaceVariant)
            .padding(22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        LinearProgressIndicator(
            color = FindlyTheme.colors.primary,
            trackColor = FindlyTheme.colors.surface,
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(FindlyTheme.corner.pill)),
        )
        if (message != null) {
            Text(
                text = message,
                color = FindlyTheme.colors.subtleText,
                style = FindlyTheme.typography.bodyMedium,
            )
        }
    }
}
