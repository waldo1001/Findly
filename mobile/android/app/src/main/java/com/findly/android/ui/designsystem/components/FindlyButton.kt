package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme
import com.findly.android.ui.designsystem.token.ButtonDisabledLabel

/** The three sanctioned button treatments — never construct a raw Material3 Button with ad-hoc
 * colors outside the design system. [Destructive] shares [Secondary]'s geometry (never a filled
 * red button — design 2a "Ember / Dusk" handoff,
 * design/findly-design-system/2a-ember-dusk/HANDOFF.md). */
enum class FindlyButtonStyle { Primary, Secondary, Destructive }

private val ButtonLabelStyle = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold)

/**
 * A stateless, presentational button. Reads only [FindlyTheme] tokens — no hardcoded colors,
 * spacing, or corner radius (specs/003-android-client.md §4.3). Geometry/states from design 2a
 * (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `FindlyButton — primary`/`— secondary`):
 * pill radius, 52dp height (48dp via [compact], for inline use in a header row), a themed focus
 * ring, and — Android's own idiom, not cross-ported from iOS's opacity dim — the platform ripple
 * for the pressed state (HANDOFF.md "Interactions & behaviour": "Presses: opacity dim on iOS,
 * ripple on Android. Do not cross-port." — the default `LocalIndication` inside `FindlyTheme`'s
 * `MaterialTheme` wrapper already renders that ripple; nothing extra is wired here).
 */
@Composable
fun FindlyButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    style: FindlyButtonStyle = FindlyButtonStyle.Primary,
    compact: Boolean = false,
) {
    val colors = FindlyTheme.colors
    val shape = RoundedCornerShape(FindlyTheme.corner.pill)
    val height = if (compact) 48.dp else 52.dp

    val background: Color
    val onBackground: Color
    val borderColor: Color?
    when {
        !enabled -> {
            background = colors.surfaceVariant
            onBackground = ButtonDisabledLabel
            borderColor = null
        }
        style == FindlyButtonStyle.Primary -> {
            background = colors.primary
            onBackground = colors.onPrimary
            borderColor = null
        }
        style == FindlyButtonStyle.Secondary -> {
            background = Color.Transparent
            onBackground = colors.onSurface
            borderColor = colors.outlineStrong
        }
        else -> { // Destructive — Secondary's geometry, danger border + label, never a filled button.
            background = Color.Transparent
            onBackground = colors.danger
            borderColor = colors.danger
        }
    }

    val interactionSource = remember { MutableInteractionSource() }
    val isFocused by interactionSource.collectIsFocusedAsState()

    var shaped = modifier
        .defaultMinSize(minHeight = height)
        .wrapContentHeight()
        .then(
            if (enabled && style == FindlyButtonStyle.Primary) {
                // level2 shadow, tinted with `primary` at 35% on light only; a plain neutral
                // shadow in dark (HANDOFF.md: "level2 shadow tinted rgba(58,70,200,.35) on
                // light").
                val tint = if (colors.isDark) {
                    Color.Black.copy(alpha = colors.shadowLevel2Alpha)
                } else {
                    colors.primary.copy(alpha = 0.35f)
                }
                Modifier.shadow(elevation = FindlyTheme.elevation.level2, shape = shape, ambientColor = tint, spotColor = tint)
            } else {
                Modifier
            },
        )
        .clip(shape)
        .background(background)

    if (borderColor != null) {
        shaped = shaped.border(width = 1.5.dp, color = borderColor, shape = shape)
    }
    if (isFocused && enabled) {
        // HANDOFF.md: "Focused: 3px `surface` ring then 3px `rgba(58,70,200,.55)`" — a two-layer
        // ring (an outer `surface` separator, then the tinted ring). `Modifier.border` stacks
        // strokes at the same outer edge rather than nesting them outward, so two chained
        // `.border()` calls here would just paint over each other; a single 3dp `primary`-tinted
        // ring (alpha-derived from the theme's own token, correct in both themes) is used instead
        // as a faithful-but-simplified stand-in for the two-tone ring.
        shaped = shaped.border(width = 3.dp, color = colors.primary.copy(alpha = 0.55f), shape = shape)
    }

    val ripple = LocalIndication.current
    val interactive = if (enabled) {
        shaped.clickable(interactionSource = interactionSource, indication = ripple, onClick = onClick)
    } else {
        shaped.semantics { disabled() }
    }

    Text(
        text = text,
        color = onBackground,
        style = ButtonLabelStyle,
        modifier = interactive.padding(horizontal = FindlyTheme.spacing.lg, vertical = FindlyTheme.spacing.sm),
    )
}
