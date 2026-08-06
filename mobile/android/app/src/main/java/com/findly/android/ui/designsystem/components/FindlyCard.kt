package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A stateless surface container. Reads only [FindlyTheme] tokens (specs/003-android-client.md
 * §4.3). Design 2a (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `FindlyCard`): radius
 * `md` (20dp), fill `surfaceVariant`, no border, no shadow. Cards are containers for rows; rows
 * inside are meant to be divided by a 1px `outline` line rather than a gap between them — that is
 * the caller's responsibility (e.g. via [androidx.compose.material3.HorizontalDivider] colored
 * `FindlyTheme.colors.outline` between children), since this component only owns the container,
 * not its content's internal layout.
 */
@Composable
fun FindlyCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(FindlyTheme.corner.md))
            .background(FindlyTheme.colors.surfaceVariant)
            .padding(FindlyTheme.spacing.md),
        content = content,
    )
}
