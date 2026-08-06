package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The spacing scale (specs/003-android-client.md §4.1/§4.2).
 *
 * Kotlin identifier note: the semantic token name is `2xl` (per the shared cross-platform
 * vocabulary in the A1 task brief) but `2xl` is not a legal Kotlin identifier (cannot start with
 * a digit). The property below is named [xxl] and MUST be treated as the same token as `2xl` by
 * any future design-generation tool targeting this contract.
 */
@Immutable
data class FindlySpacingTokens(
    val xs: Dp,
    val sm: Dp,
    val md: Dp,
    val lg: Dp,
    val xl: Dp,
    val xxl: Dp,
)

// Design 2a — "Ember / Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md).
val FindlySpacing = FindlySpacingTokens(
    xs = 4.dp,
    sm = 8.dp,
    md = 12.dp,
    lg = 20.dp,
    xl = 28.dp,
    xxl = 40.dp,
)

val LocalFindlySpacing = staticCompositionLocalOf { FindlySpacing }
