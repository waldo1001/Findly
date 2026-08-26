package com.findly.android.ui.designsystem.components

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.findly.android.ui.designsystem.FindlyTheme
import kotlinx.coroutines.launch

/**
 * specs/010-app-shell-and-screen-ux.md §1.2/§3.1, added to the 003 §4.3 component contract — the
 * roster's three-detent bottom sheet. **Minimized 186dp**, **standard 440dp**, **expanded**
 * (this component's own "large" detent — [EXPANDED_FRACTION] of the available height, since
 * Compose has no OS-level "large detent" primitive the way `.presentationDetents` does on iOS).
 * The map stays fully rendered and interactive behind the sheet at every detent — this component
 * never covers or unmounts it, it only occupies the bottom edge.
 *
 * Stateless/presentational like every other design-system component (003 §4.3): [state] is
 * caller-owned ([rememberFindlyBottomSheetState]), [content] is a plain composable slot the
 * caller fully controls. Platform-native mechanics underneath — a drag gesture snapping to the
 * three anchors — are this component's own implementation detail, the same category
 * [FindlyNavDrawer]'s doc describes for `ModalNavigationDrawer`-class behavior.
 *
 * **Dragging between detents MUST NOT unmount [content] or re-create its view models** (the I16
 * `@StateObject`-ownership rule, restated for Android in 010 §3.1): [content] is composed exactly
 * once per call to [FindlyBottomSheet], unconditionally on every detent — this component only
 * changes the *visible height* of the surface wrapping it, never which composable is in the tree.
 */
enum class FindlyBottomSheetDetent { Minimized, Standard, Expanded }

val FindlyBottomSheetMinimizedHeight: Dp = 186.dp
val FindlyBottomSheetStandardHeight: Dp = 440.dp

/** Fraction of the available height the "expanded" detent occupies — Compose's stand-in for
 * iOS's `.large` `UISheetPresentationController.Detent`, which has no fixed height. */
private const val EXPANDED_FRACTION = 0.92f

@Stable
class FindlyBottomSheetState(initial: FindlyBottomSheetDetent) {
    var detent: FindlyBottomSheetDetent by mutableStateOf(initial)
        internal set

    /** Programmatic detent change (e.g. selecting a member expands the sheet to `Standard` so
     * `Locate now` is visible) — the same underlying mechanism a drag-driven snap uses. */
    fun snapTo(target: FindlyBottomSheetDetent) {
        detent = target
    }
}

@Composable
fun rememberFindlyBottomSheetState(
    initial: FindlyBottomSheetDetent = FindlyBottomSheetDetent.Standard,
): FindlyBottomSheetState = remember { FindlyBottomSheetState(initial) }

@Composable
fun FindlyBottomSheet(
    state: FindlyBottomSheetState,
    modifier: Modifier = Modifier,
    header: @Composable ColumnScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val maxHeightPx = with(density) { maxHeight.toPx() }
        val minimizedPx = with(density) { FindlyBottomSheetMinimizedHeight.toPx() }
        val standardPx = with(density) { FindlyBottomSheetStandardHeight.toPx() }
        val expandedPx = maxHeightPx * EXPANDED_FRACTION

        fun pxFor(detent: FindlyBottomSheetDetent): Float = when (detent) {
            FindlyBottomSheetDetent.Minimized -> minimizedPx
            FindlyBottomSheetDetent.Standard -> standardPx
            FindlyBottomSheetDetent.Expanded -> expandedPx
        }

        fun nearestDetent(px: Float): FindlyBottomSheetDetent =
            listOf(
                FindlyBottomSheetDetent.Minimized to minimizedPx,
                FindlyBottomSheetDetent.Standard to standardPx,
                FindlyBottomSheetDetent.Expanded to expandedPx,
            ).minByOrNull { (_, anchorPx) -> kotlin.math.abs(anchorPx - px) }!!.first

        val heightPx = remember { Animatable(pxFor(state.detent)) }
        val scope = rememberCoroutineScope()

        // A programmatic snapTo (state.detent changed by the caller, not by a drag) animates the
        // surface to the new anchor.
        LaunchedEffect(state.detent) {
            heightPx.animateTo(pxFor(state.detent))
        }

        var dragAccumulatorPx by remember { mutableFloatStateOf(pxFor(state.detent)) }

        val draggableState = rememberDraggableState { delta ->
            dragAccumulatorPx = (dragAccumulatorPx - delta).coerceIn(minimizedPx, expandedPx)
            scope.launch { heightPx.snapTo(dragAccumulatorPx) }
        }

        val heightDp = with(density) { heightPx.value.toDp() }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(heightDp)
                .shadow(elevation = FindlyTheme.elevation.level3, shape = RoundedCornerShape(topStart = FindlyTheme.corner.lg, topEnd = FindlyTheme.corner.lg))
                .clip(RoundedCornerShape(topStart = FindlyTheme.corner.lg, topEnd = FindlyTheme.corner.lg))
                .background(FindlyTheme.colors.surface)
                .windowInsetsPadding(WindowInsets.navigationBars),
        ) {
            // The grabber row is the drag target — dragging anywhere on it moves the sheet;
            // releasing snaps to whichever of the three anchors is nearest.
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .draggable(
                        state = draggableState,
                        orientation = Orientation.Vertical,
                        onDragStarted = { dragAccumulatorPx = heightPx.value },
                        onDragStopped = {
                            val target = nearestDetent(dragAccumulatorPx)
                            state.snapTo(target)
                            heightPx.animateTo(pxFor(target))
                        },
                    )
                    .padding(vertical = FindlyTheme.spacing.sm),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    modifier = Modifier
                        .size(width = 36.dp, height = 4.dp)
                        .clip(CircleShape)
                        .background(FindlyTheme.colors.outline),
                ) {}
                header()
            }

            content()
        }
    }
}
