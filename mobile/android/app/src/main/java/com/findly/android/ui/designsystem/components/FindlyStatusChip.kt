package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

/** Semantic tone for a status chip — maps 1:1 onto a color token, never a raw color. Names kept
 * as-is (existing call sites use them) even though design 2a's own vocabulary is
 * online/stale/paused/danger — [Success] = online, [Warning] = stale, [Neutral] = paused. */
enum class FindlyStatusTone { Success, Warning, Danger, Neutral }

private val ChipLabelStyle = TextStyle(fontSize = 10.5.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.3.sp)

/** The tone's mandatory glyph — status is never color alone (HANDOFF.md `StatusChip`: "always
 * glyph + word" / "Status is never colour alone. Greyscale must remain readable."). */
private fun glyphFor(tone: FindlyStatusTone): String = when (tone) {
    FindlyStatusTone.Success -> "●" // ●
    FindlyStatusTone.Warning -> "▲" // ▲
    FindlyStatusTone.Neutral -> "▮▮" // ▮▮
    FindlyStatusTone.Danger -> "✕" // ✕
}

/**
 * A small pill-shaped status indicator (device registered / paused / stale / error, …). Reads
 * only [FindlyTheme] tokens (specs/003-android-client.md §4.3). Geometry/states from design 2a
 * (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `StatusChip`): 24dp height, pill radius,
 * a mandatory leading glyph per tone so status never reads by color alone. [label] is prefixed
 * with the glyph rather than callers spelling it out, so every existing call site (screens are
 * out of scope for this task) gets the greyscale-readable treatment for free.
 *
 * [Success]/[Warning] fills use [FindlyTheme.colors.onDanger] as their text/glyph color rather
 * than a bespoke "on-success"/"on-warning" token — the 11-role contract has neither, and
 * `onDanger` is exactly the color the handoff already picked to contrast against a saturated fill
 * in both themes (white in light, `#2A0708` in dark), which is what HANDOFF.md's "onDanger-white
 * text" phrasing for the online chip literally names.
 */
@Composable
fun FindlyStatusChip(
    label: String,
    tone: FindlyStatusTone,
    modifier: Modifier = Modifier,
) {
    val colors = FindlyTheme.colors
    val background: Color
    val onBackground: Color
    val borderColor: Color?
    when (tone) {
        FindlyStatusTone.Success -> {
            background = colors.success
            onBackground = colors.onDanger
            borderColor = null
        }
        FindlyStatusTone.Warning -> {
            background = colors.warning
            onBackground = colors.onDanger
            borderColor = null
        }
        FindlyStatusTone.Danger -> {
            background = colors.danger
            onBackground = colors.onDanger
            borderColor = null
        }
        FindlyStatusTone.Neutral -> {
            background = Color.Transparent
            onBackground = colors.onSurface
            borderColor = colors.outlineStrong
        }
    }

    var chipModifier = modifier
        .height(24.dp)
        .clip(RoundedCornerShape(FindlyTheme.corner.pill))
        .background(background)
    if (borderColor != null) {
        chipModifier = chipModifier.border(width = 1.5.dp, color = borderColor, shape = RoundedCornerShape(FindlyTheme.corner.pill))
    }

    Text(
        text = "${glyphFor(tone)} $label",
        color = onBackground,
        style = ChipLabelStyle,
        modifier = chipModifier
            .wrapContentHeight()
            .padding(horizontal = 9.dp),
    )
}
