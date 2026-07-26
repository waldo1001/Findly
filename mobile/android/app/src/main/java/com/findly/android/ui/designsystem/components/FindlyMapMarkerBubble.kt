package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.drawBehind
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * The three [FindlyMapMarkerBubble] visual states (design/findly-design-system/README.md's
 * `MapMarkerBubble` spec: "Online = solid fill + success pointer tail; stale = desaturated +
 * dashed ring; no-location-yet = neutral '?' chip, not falsely placed on the map"). Deriving
 * *which* state applies from a `RosterDeviceUi`/`GroupMapMemberUi` is pure, unit-tested logic
 * (`ui/map/MapMarkerState.kt`'s `markerStateFor` — 001-api-contract.md §5.2's `isStale` is
 * computed server-side and MUST NOT be recomputed by the client); this component only renders
 * whichever state it is given.
 */
enum class FindlyMapMarkerState { Online, Stale, NoLocation }

/**
 * A family member's position bubble on the live map (001-api-contract.md §5.2/§12.10, A12).
 * Stateless — reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3). Shared by
 * [com.findly.android.ui.map.PlaceholderMapRenderer] (label-only, no real projection) and the
 * real Google Maps renderer (as `MarkerComposable` content) so both always render the identical
 * three marker states — family map and group map (position-only, 001 §12.10) use the same visual
 * language.
 */
@Composable
fun FindlyMapMarkerBubble(
    label: String,
    state: FindlyMapMarkerState,
    modifier: Modifier = Modifier,
) {
    when (state) {
        FindlyMapMarkerState.NoLocation -> NoLocationChip(modifier = modifier)
        FindlyMapMarkerState.Online -> LabelBubble(
            label = label,
            fill = FindlyTheme.colors.success,
            dashed = false,
            tail = true,
            modifier = modifier,
        )
        FindlyMapMarkerState.Stale -> LabelBubble(
            label = label,
            fill = FindlyTheme.colors.outline,
            dashed = true,
            tail = false,
            modifier = modifier,
        )
    }
}

/** No fix yet — a neutral "?" chip rather than a colored bubble, so it never reads as a real
 * (possibly wrong) position. Callers are responsible for not placing this at any default
 * coordinate on the actual map (specs/003-android-client.md §12.1) — this component only renders
 * the chip's content. */
@Composable
private fun NoLocationChip(modifier: Modifier = Modifier) {
    Text(
        text = "?",
        color = FindlyTheme.colors.onSurface,
        style = FindlyTheme.typography.labelSmall,
        modifier = modifier
            .clip(RoundedCornerShape(FindlyTheme.corner.pill))
            .background(FindlyTheme.colors.surfaceVariant)
            .border(
                width = FindlyTheme.elevation.level1,
                color = FindlyTheme.colors.outline,
                shape = RoundedCornerShape(FindlyTheme.corner.pill),
            )
            .padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.xs),
    )
}

@Composable
private fun LabelBubble(
    label: String,
    fill: Color,
    dashed: Boolean,
    tail: Boolean,
    modifier: Modifier = Modifier,
) {
    val ringColor = FindlyTheme.colors.surface
    val ringWidth = FindlyTheme.elevation.level1

    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
        Text(
            text = label,
            color = FindlyTheme.colors.onPrimary,
            style = FindlyTheme.typography.labelSmall,
            modifier = Modifier
                .clip(RoundedCornerShape(FindlyTheme.corner.pill))
                .background(fill)
                .then(
                    if (dashed) {
                        Modifier.dashedRing(color = ringColor, strokeWidth = ringWidth)
                    } else {
                        Modifier.border(width = ringWidth, color = ringColor, shape = RoundedCornerShape(FindlyTheme.corner.pill))
                    },
                )
                .padding(horizontal = FindlyTheme.spacing.sm, vertical = FindlyTheme.spacing.xs),
        )
        if (tail) {
            MarkerTail(fill = fill)
        }
    }
}

/** The "pointer tail" a real map pin needs so it visually anchors to a single point rather than
 * floating above it — online markers only (design system spec). A small filled triangle drawn
 * directly below the bubble, same fill color. */
@Composable
private fun MarkerTail(fill: Color) {
    androidx.compose.foundation.Canvas(
        modifier = Modifier.size(width = FindlyTheme.spacing.md, height = FindlyTheme.spacing.sm),
    ) {
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(size.width, 0f)
            lineTo(size.width / 2f, size.height)
            close()
        }
        drawPath(path, color = fill)
    }
}

/** A dashed ring around the bubble (stale state) — `Modifier.border` has no dashed variant, so
 * this draws one directly with a dash [PathEffect], matching [FindlyTheme.corner.pill]'s fully
 * rounded shape. */
private fun Modifier.dashedRing(color: Color, strokeWidth: androidx.compose.ui.unit.Dp): Modifier =
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
