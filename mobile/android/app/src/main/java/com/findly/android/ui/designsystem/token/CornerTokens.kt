package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Corner-radius scale (specs/003-android-client.md §4.1/§4.2). `pill` is large enough to always
 * round a component's shorter edge to a full stadium/circle regardless of its size. */
@Immutable
data class FindlyCornerTokens(
    val sm: Dp,
    val md: Dp,
    val lg: Dp,
    val pill: Dp,
)

// Design 2a — "Ember / Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md).
val FindlyCorner = FindlyCornerTokens(
    sm = 12.dp,
    md = 20.dp,
    lg = 28.dp,
    pill = 999.dp,
)

val LocalFindlyCorner = staticCompositionLocalOf { FindlyCorner }
