package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Elevation scale (specs/003-android-client.md §4.1/§4.2). */
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
    level3 = 6.dp,
)

val LocalFindlyElevation = staticCompositionLocalOf { FindlyElevation }
