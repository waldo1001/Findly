package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Elevation scale (specs/003-android-client.md §4.1/§4.2). Android dp values from design 2a —
 * "Ember / Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md); the matching shadow
 * opacity per level/theme lives on [com.findly.android.ui.designsystem.token.FindlyColorTokens]
 * (`shadowLevel1Alpha`/`2`/`3`) since it varies by theme and this singleton doesn't. */
@Immutable
data class FindlyElevationTokens(
    val level0: Dp,
    val level1: Dp,
    val level2: Dp,
    val level3: Dp,
)

val FindlyElevation = FindlyElevationTokens(
    level0 = 0.dp,
    level1 = 1.dp,
    level2 = 3.dp,
    level3 = 8.dp,
)

val LocalFindlyElevation = staticCompositionLocalOf { FindlyElevation }
