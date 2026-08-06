package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * The three [FindlyMapMarkerBubble] visual states (design 2a — "Ember / Dusk",
 * design/findly-design-system/2a-ember-dusk/HANDOFF.md's `MapMarkerBubble` spec: online = solid
 * `primary` fill + a "NOW" pill; stale = `surface` fill with a dashed `warning` ring; no-location
 * = a neutral "?" circle, never falsely placed on the map). Deriving *which* state applies from a
 * `RosterDeviceUi`/`GroupMapMemberUi` is pure, unit-tested logic (`ui/map/MapMarkerState.kt`'s
 * `markerStateFor` — 001-api-contract.md §5.2's `isStale` is computed server-side and MUST NOT be
 * recomputed by the client); this component only renders whichever state it is given.
 */
enum class FindlyMapMarkerState { Online, Stale, NoLocation }

private val MarkerNameStyle = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
private val NowPillStyle = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.ExtraBold)
private val StaleAgeStyle = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold)

/**
 * A family member's position bubble on the live map (001-api-contract.md §5.2/§12.10, A12).
 * Stateless — reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3). Shared by
 * [com.findly.android.ui.map.PlaceholderMapRenderer] (label-only, no real projection) and the
 * real Google Maps renderer (as `MarkerComposable` content) so both always render the identical
 * three marker states — family map and group map (position-only, 001 §12.10) use the same visual
 * language.
 *
 * [staleAgeText] is the HANDOFF.md "▲ 24m" trailing metadata on a [FindlyMapMarkerState.Stale]
 * bubble — optional (`null` omits the trailing pill) since computing "how long ago" from a
 * `lastFixAt` timestamp is a screen/state-holder concern (A27), not this component's.
 */
@Composable
fun FindlyMapMarkerBubble(
    label: String,
    state: FindlyMapMarkerState,
    modifier: Modifier = Modifier,
    staleAgeText: String? = null,
) {
    when (state) {
        FindlyMapMarkerState.NoLocation -> NoLocationCircle(modifier = modifier)
        FindlyMapMarkerState.Online -> OnlineBubble(label = label, modifier = modifier)
        FindlyMapMarkerState.Stale -> StaleBubble(label = label, ageText = staleAgeText, modifier = modifier)
    }
}

/** No fix yet — a neutral "?" circle rather than a colored bubble, so it never reads as a real
 * (possibly wrong) position. HANDOFF.md: "52pt circle, surfaceVariant fill, 2px dashed outline,
 * '?' glyph. Not placed on the map — shown as the row's leading element only when a device has
 * never checked in." Callers are responsible for not placing this at any default coordinate on
 * the actual map (specs/003-android-client.md §12.1) — this component only renders the circle.
 *
 * A26 code-review fix (Major 4): the dashed ring uses [FindlyTheme.colors.outlineStrong], not the
 * decorative `outline` HANDOFF.md's prose names — this ring is the primary cue that a device has
 * never reported, i.e. a stroke that carries meaning, the same reasoning already applied to
 * `FindlyButton`'s secondary border, `FindlyStatusChip`'s paused border, and
 * `FindlyTextField`'s default border. */
@Composable
private fun NoLocationCircle(modifier: Modifier = Modifier) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(52.dp)
            .clip(CircleShape)
            .background(FindlyTheme.colors.surfaceVariant)
            .dashedRing(color = FindlyTheme.colors.outlineStrong, strokeWidth = 2.dp),
    ) {
        Text(
            text = "?",
            color = FindlyTheme.colors.onSurface,
            style = MarkerNameStyle,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun OnlineBubble(label: String, modifier: Modifier = Modifier) {
    val colors = FindlyTheme.colors
    val shape = RoundedCornerShape(FindlyTheme.corner.pill)
    val shadowTint = Color.Black.copy(alpha = colors.shadowLevel3Alpha)

    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
            modifier = Modifier
                .height(44.dp)
                .shadow(elevation = FindlyTheme.elevation.level3, shape = shape, ambientColor = shadowTint, spotColor = shadowTint)
                .clip(shape)
                .background(colors.primary)
                .padding(start = 6.dp, end = 12.dp),
        ) {
            // 32pt circular avatar. Photo/initials rendering is Bucket B
            // (design/findly-design-system/2a-ember-dusk/HANDOFF.md "Bucket A vs bucket B") — a
            // solid onPrimary circle is the Bucket-A placeholder.
            Column(modifier = Modifier.size(32.dp).clip(CircleShape).background(colors.onPrimary)) {}

            Text(text = label, color = colors.onPrimary, style = MarkerNameStyle)

            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .height(18.dp)
                    .clip(RoundedCornerShape(FindlyTheme.corner.pill))
                    .background(colors.markerOnlineDot)
                    .padding(horizontal = 6.dp),
            ) {
                Text(text = "● NOW", color = colors.markerOnlineDotOn, style = NowPillStyle)
            }
        }
        MarkerTail(fill = colors.primary)
    }
}

@Composable
private fun StaleBubble(label: String, ageText: String?, modifier: Modifier = Modifier) {
    val colors = FindlyTheme.colors
    val shape = RoundedCornerShape(FindlyTheme.corner.pill)

    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
            modifier = Modifier
                .height(44.dp)
                .clip(shape)
                .background(colors.surface)
                .dashedRing(color = colors.warning, strokeWidth = 2.dp)
                .padding(start = 6.dp, end = 12.dp),
        ) {
            Column(modifier = Modifier.size(32.dp).clip(CircleShape).background(colors.surfaceVariant)) {}
            Text(text = label, color = colors.onSurface, style = MarkerNameStyle)
            if (ageText != null) {
                Text(text = "▲ $ageText", color = colors.warning, style = StaleAgeStyle)
            }
        }
        MarkerTail(fill = colors.surface)
    }
}

/** The "pointer tail" a real map pin needs so it visually anchors to a single point rather than
 * floating above it. A small filled triangle drawn directly below the bubble, 7pt tall
 * (HANDOFF.md: "7pt triangular tail below in primary"). */
@Composable
private fun MarkerTail(fill: Color) {
    Canvas(modifier = Modifier.size(width = 14.dp, height = 7.dp)) {
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(size.width, 0f)
            lineTo(size.width / 2f, size.height)
            close()
        }
        drawPath(path, color = fill)
    }
}

/** A dashed ring matching the shape's own corner radius (works for both a pill bubble and a full
 * circle, since a circle is just a rounded rect whose corner radius is its own half-size). */
private fun Modifier.dashedRing(color: Color, strokeWidth: Dp): Modifier =
    this.drawBehind {
        val strokeWidthPx = strokeWidth.toPx()
        val cornerRadiusPx = size.minDimension / 2f
        drawRoundRect(
            color = color,
            cornerRadius = CornerRadius(cornerRadiusPx, cornerRadiusPx),
            style = Stroke(
                width = strokeWidthPx,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f), 0f),
            ),
        )
    }
