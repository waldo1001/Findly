package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import com.findly.android.ui.designsystem.FindlyTheme

/** The two sanctioned button treatments — never construct a raw Material3 Button with ad-hoc
 * colors outside the design system. */
enum class FindlyButtonStyle { Primary, Secondary }

/**
 * A stateless, presentational button. Reads only [FindlyTheme] tokens — no hardcoded colors,
 * spacing, or corner radius (specs/003-android-client.md §4.3).
 */
@Composable
fun FindlyButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    style: FindlyButtonStyle = FindlyButtonStyle.Primary,
) {
    val background: Color
    val onBackground: Color
    when (style) {
        FindlyButtonStyle.Primary -> {
            background = FindlyTheme.colors.primary
            onBackground = FindlyTheme.colors.onPrimary
        }
        FindlyButtonStyle.Secondary -> {
            background = FindlyTheme.colors.surfaceVariant
            onBackground = FindlyTheme.colors.onSurface
        }
    }

    val clickableModifier = if (enabled) {
        modifier.clickable(onClick = onClick)
    } else {
        modifier.alpha(0.5f).semantics { disabled() }
    }

    Text(
        text = text,
        color = onBackground,
        style = FindlyTheme.typography.titleMedium,
        modifier = clickableModifier
            .clip(RoundedCornerShape(FindlyTheme.corner.md))
            .background(background)
            .padding(horizontal = FindlyTheme.spacing.lg, vertical = FindlyTheme.spacing.sm),
    )
}
