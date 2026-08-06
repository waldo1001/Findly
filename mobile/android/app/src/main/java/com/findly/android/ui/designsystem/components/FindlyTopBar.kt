package com.findly.android.ui.designsystem.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.findly.android.ui.designsystem.FindlyTheme

/**
 * The one central "can this screen go back?" answer, provided once by
 * [com.findly.android.ui.nav.FindlyNavHost] and consumed by every [FindlyTopBar] (specs/003 §12.5,
 * mirroring specs/004 §2.5's iOS `navBarBackAction` environment value).
 *
 * Threading an `onBack` parameter through all 14 screens would put the "should there be a back
 * button here?" decision back in each screen — which is how every screen ended up with **no**
 * visible back affordance at all, leaving the system back gesture as the only way out.
 *
 * `null` means "this is a start destination, there is nothing to pop".
 */
val LocalNavBackAction = compositionLocalOf<(() -> Unit)?> { null }

private val TopBarTitleStyle = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.2).sp)

/**
 * A stateless top app bar. Reads only [FindlyTheme] tokens (specs/003-android-client.md §4.3).
 * Geometry from design 2a (design/findly-design-system/2a-ember-dusk/HANDOFF.md, `FindlyTopBar /
 * NavBar`): 52dp height, a 44×44dp back touch target with a 22pt `primary` chevron, title 18/600
 * at −0.2 tracking.
 *
 * When [navigationIcon] is not supplied, the bar renders a back control iff [LocalNavBackAction] is
 * non-null — so screens get the correct affordance without opting in.
 */
@Composable
fun FindlyTopBar(
    title: String,
    modifier: Modifier = Modifier,
    navigationIcon: (@Composable () -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    val backAction = LocalNavBackAction.current
    val resolvedNavigationIcon: (@Composable () -> Unit)? = navigationIcon
        ?: backAction?.let {
            {
                // A themed text glyph rather than a Material icon: this module deliberately has no
                // material-icons dependency, and the design system's rule is that components read
                // only FindlyTheme tokens (specs/003 §4.3). "‹" mirrors correctly under RTL
                // layout direction. 44x44dp touch target per HANDOFF.md, the 22pt chevron centered
                // within it.
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(44.dp)
                        .clickable(onClick = it)
                        .semantics { contentDescription = "Back" },
                ) {
                    Text(
                        text = "‹",
                        color = FindlyTheme.colors.primary,
                        style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
                    )
                }
            }
        }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .background(FindlyTheme.colors.surface)
            .padding(horizontal = FindlyTheme.spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(FindlyTheme.spacing.sm),
    ) {
        resolvedNavigationIcon?.invoke()

        Text(
            text = title,
            color = FindlyTheme.colors.onSurface,
            style = TopBarTitleStyle,
            modifier = Modifier.weight(1f),
        )

        actions()
    }
}
