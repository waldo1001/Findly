package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** The six normative type roles (specs/003-android-client.md §4.1/§4.2). Same values in light
 * and dark — only [com.findly.android.ui.designsystem.token.FindlyColorTokens] varies by
 * theme. */
@Immutable
data class FindlyTypographyTokens(
    val displayLarge: TextStyle,
    val titleLarge: TextStyle,
    val titleMedium: TextStyle,
    val bodyLarge: TextStyle,
    val bodyMedium: TextStyle,
    val labelSmall: TextStyle,
)

// Design 2a — "Ember / Dusk" (design/findly-design-system/2a-ember-dusk/HANDOFF.md) — platform
// system font (Roboto); sizes in sp. `labelSmall` is additionally uppercase per HANDOFF.md
// ("12 / 700, uppercase") — Compose `TextStyle` has no text-transform, so callers that use
// `labelSmall` (`FindlyStatusChip`, `FindlySectionHeader`) uppercase the string itself.
val FindlyTypography = FindlyTypographyTokens(
    displayLarge = TextStyle(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp),
    titleLarge = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp),
    titleMedium = TextStyle(fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 24.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal),
    labelSmall = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp),
)

val LocalFindlyTypography = staticCompositionLocalOf { FindlyTypography }
