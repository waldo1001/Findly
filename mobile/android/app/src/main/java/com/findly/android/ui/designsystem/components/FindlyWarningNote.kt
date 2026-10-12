package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * A sentence-length warning surface (specs/003-android-client.md §4.3, D21): an optional bold
 * [lead] followed by [body], with a `warning`-token accent stripe and a `▲` glyph so the warning
 * is never colour alone (same rule as [FindlyStatusChip], which is a fixed-height pill and cannot
 * carry a sentence). Plain strings only, `FindlyTheme.*` tokens only — no screen-specific
 * dependency. First use: the 005 §2.5 item-2 no-end-date warning.
 */
@Composable
fun FindlyWarningNote(
    body: String,
    modifier: Modifier = Modifier,
    lead: String? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .clip(RoundedCornerShape(FindlyTheme.corner.md))
            .background(FindlyTheme.colors.surfaceVariant),
    ) {
        Column(
            modifier = Modifier
                .width(4.dp)
                .fillMaxHeight()
                .background(FindlyTheme.colors.warning),
        ) {}
        Row(
            modifier = Modifier.padding(FindlyTheme.spacing.md),
            horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
        ) {
            Text(text = "▲", color = FindlyTheme.colors.warning, style = FindlyTheme.typography.bodyMedium)
            Text(
                text = buildAnnotatedString {
                    if (lead != null) {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(lead) }
                        append(" ")
                    }
                    append(body)
                },
                color = FindlyTheme.colors.onSurface,
                style = FindlyTheme.typography.bodyMedium,
            )
        }
    }
}
