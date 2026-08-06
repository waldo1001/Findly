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
 * An error placeholder with an optional retry action. Stateless, reads only [FindlyTheme] tokens
 * (specs/003-android-client.md §4.3). `message` is expected to already be a localized/UX string
 * — [com.findly.android.network.ApiError] mapping to user-facing text is a ViewModel/screen
 * concern (A2), not this component's; that mapping is also where "name the device, explain in
 * plain words" (below) actually happens — this component only renders whatever string it's given.
 *
 * Design 2a (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `EmptyState / LoadingState /
 * ErrorState`): radius `lg`, `surfaceVariant` fill, 22dp padding, title `titleMedium` (18/600)
 * lead with a `▲` in `warning` — **not `danger`/red**: "an unreachable device is not an error
 * state for the user" — body `bodyMedium` (15/400) at 1.5x line height in the muted color, single
 * action. "Raw server text never reaches the screen" is the caller's obligation (this component
 * has no server/`ApiError` dependency to enforce it against).
 */
@Composable
fun FindlyErrorState(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    onRetry: (() -> Unit)? = null,
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
            text = "▲ $title",
            color = FindlyTheme.colors.warning,
            style = FindlyTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
        )
        Text(
            text = message,
            color = FindlyTheme.colors.subtleText,
            style = FindlyTheme.typography.bodyMedium.copy(lineHeight = 22.5.sp),
            textAlign = TextAlign.Center,
        )
        if (onRetry != null) {
            FindlyButton(
                text = "Retry",
                onClick = onRetry,
                style = FindlyButtonStyle.Secondary,
            )
        }
    }
}
