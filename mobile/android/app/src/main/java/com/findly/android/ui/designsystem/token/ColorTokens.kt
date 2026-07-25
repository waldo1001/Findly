package com.findly.android.ui.designsystem.token

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * The color half of the design-token contract (specs/003-android-client.md §4.1/§4.2).
 * These are the ONLY color values allowed to exist anywhere in the app outside this file —
 * every component reads [com.findly.android.ui.designsystem.FindlyTheme.colors] instead of
 * constructing a [Color] literal.
 */
@Immutable
data class FindlyColorTokens(
    val primary: Color,
    val onPrimary: Color,
    val secondary: Color,
    val surface: Color,
    val onSurface: Color,
    val surfaceVariant: Color,
    val danger: Color,
    val onDanger: Color,
    val success: Color,
    val warning: Color,
    val outline: Color,
)

/**
 * "Findly — Family Location Design System" (design/findly-design-system/, 2026-07-20).
 * Calm teal-forward palette; every text/essential-icon pairing verified WCAG 2.1 AA
 * (ratios in design/findly-design-system/README.md and specs/003 §4.2). Fully swappable via this seam.
 */
val LightFindlyColors = FindlyColorTokens(
    primary = Color(0xFF00696E),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF4C5FD5),
    surface = Color(0xFFFAFAF7),
    onSurface = Color(0xFF1B1D1C),
    surfaceVariant = Color(0xFFEEEEE9),
    danger = Color(0xFFC0362C),
    onDanger = Color(0xFFFFFFFF),
    success = Color(0xFF1E7D46),
    warning = Color(0xFF8A5A00),
    outline = Color(0xFFC9C8C2),
)

val DarkFindlyColors = FindlyColorTokens(
    primary = Color(0xFF4CD4D9),
    onPrimary = Color(0xFF00312F),
    secondary = Color(0xFFA9B4FF),
    surface = Color(0xFF17181A),
    onSurface = Color(0xFFECECE6),
    surfaceVariant = Color(0xFF24262A),
    danger = Color(0xFFF2867B),
    onDanger = Color(0xFF490A05),
    success = Color(0xFF5FD08A),
    warning = Color(0xFFE4B44C),
    outline = Color(0xFF3A3D42),
)

val LocalFindlyColors = staticCompositionLocalOf { LightFindlyColors }
