package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

private val ListRowTitleStyle = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
private val ListRowSubtitleStyle = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Normal)

/**
 * A stateless single-line-or-two list row (roster entries, device rows, history entries, …).
 * Reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3). Geometry from design 2a
 * (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `FindlyListRow`): 60dp minimum height,
 * 14dp horizontal / 12dp vertical padding, 12dp gap between leading/title/trailing. [leading]/
 * [trailing] stay generic composable slots (unchanged API) — the avatar/chip/chevron content the
 * handoff describes is each caller's own concern, not this component's. Pressed uses the platform
 * ripple on Android (HANDOFF.md "Interactions & behaviour": iOS gets a light overlay instead — not
 * cross-ported); [enabled] renders the whole row at 45% opacity, matching HANDOFF.md's "Disabled:
 * 45% opacity". [minHeight] defaults to the 60dp `FindlyListRow` value but is overridable — used
 * by `FindlySwitchRow` to hit its own, smaller HANDOFF.md-specified 56dp minimum without
 * duplicating this component's layout.
 */
@Composable
fun FindlyListRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    minHeight: Dp = 60.dp,
) {
    var rowModifier = modifier
        .fillMaxWidth()
        .defaultMinSize(minHeight = minHeight)
        .then(if (!enabled) Modifier.alpha(0.45f).semantics { disabled() } else Modifier)

    rowModifier = if (onClick != null && enabled) {
        rowModifier.clickable(onClick = onClick)
    } else {
        rowModifier
    }

    Row(
        modifier = rowModifier
            .background(FindlyTheme.colors.surface)
            // HANDOFF.md: "padding 12/14" (vertical/horizontal) — 14dp horizontal doesn't land on
            // a spacing step, so it's `md` (12dp, the vertical value) + a 2dp literal rather than
            // a second hardcoded constant.
            .padding(horizontal = FindlyTheme.spacing.md + 2.dp, vertical = FindlyTheme.spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.md),
    ) {
        leading?.invoke()

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                color = FindlyTheme.colors.onSurface,
                style = ListRowTitleStyle,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    color = FindlyTheme.colors.subtleText,
                    style = ListRowSubtitleStyle,
                )
            }
        }

        trailing?.invoke(this)
    }
}
