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
 * §4.3). Elevation is expressed as a [FindlyTheme.elevation]-derived surface tint rather than a
 * shadow, since Material3's tonal-elevation model already uses that approach.
 */
@Composable
fun FindlyCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(FindlyTheme.corner.lg))
            .background(FindlyTheme.colors.surfaceVariant)
            .padding(FindlyTheme.spacing.md),
        content = content,
    )
}
