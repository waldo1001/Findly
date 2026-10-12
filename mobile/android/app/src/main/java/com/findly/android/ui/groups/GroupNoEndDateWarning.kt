package com.findly.android.ui.groups

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
 * The 005 §2.5 item-2 warning, in the design system's warning style (`FindlyTheme.colors.warning`
 * stripe + the `▲` glyph, so status is never colour alone — same rule as `FindlyStatusChip`).
 * Rendered on the create screen directly under the "No end date" choice (above Create). The text
 * is [GroupPolicyCopy.NO_END_DATE_WARNING], with the lead sentence in bold per the spec's
 * formatting. A sentence-length message does not fit `FindlyStatusChip`'s 24 dp pill, hence this
 * small card-shaped sibling built from the same tokens.
 */
@Composable
fun GroupNoEndDateWarning(modifier: Modifier = Modifier) {
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
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(GroupPolicyCopy.NO_END_DATE_WARNING_LEAD) }
                    append(" ")
                    append(GroupPolicyCopy.NO_END_DATE_WARNING_BODY)
                },
                color = FindlyTheme.colors.onSurface,
                style = FindlyTheme.typography.bodyMedium,
            )
        }
    }
}
