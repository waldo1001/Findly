package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * "Nothing here yet" placeholder (e.g. no devices registered, no history in range). Stateless,
 * reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3). Design 2a
 * (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `EmptyState / LoadingState / ErrorState`):
 * radius `lg`, `surfaceVariant` fill, 22dp padding, title `titleMedium` (18/600), body
 * `bodyMedium` (15/400) at 1.5x line height in the muted color, single optional action.
 */
@Composable
fun FindlyEmptyState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
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
        Text(
            text = title,
            color = FindlyTheme.colors.onSurface,
            style = FindlyTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        Text(
            text = message,
            color = FindlyTheme.colors.subtleText,
            style = FindlyTheme.typography.bodyMedium.copy(lineHeight = 22.5.sp),
            textAlign = TextAlign.Center,
        )
        if (actionLabel != null && onAction != null) {
            FindlyButton(text = actionLabel, onClick = onAction, style = FindlyButtonStyle.Secondary)
        }
    }
}
