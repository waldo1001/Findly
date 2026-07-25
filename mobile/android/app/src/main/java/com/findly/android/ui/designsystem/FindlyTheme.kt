package com.findly.android.ui.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import com.findly.android.ui.designsystem.token.DarkFindlyColors
import com.findly.android.ui.designsystem.token.LightFindlyColors
import com.findly.android.ui.designsystem.token.LocalFindlyColors
import com.findly.android.ui.designsystem.token.LocalFindlyCorner
import com.findly.android.ui.designsystem.token.LocalFindlyElevation
import com.findly.android.ui.designsystem.token.LocalFindlySpacing
import com.findly.android.ui.designsystem.token.LocalFindlyTypography
import com.findly.android.ui.designsystem.token.FindlyColorTokens
import com.findly.android.ui.designsystem.token.FindlyCorner
import com.findly.android.ui.designsystem.token.FindlyElevation
import com.findly.android.ui.designsystem.token.FindlySpacing
import com.findly.android.ui.designsystem.token.FindlyTypography

/**
 * The only sanctioned way any composable in this app reads style. Screens/components call
 * `FindlyTheme.colors.primary`, `FindlyTheme.spacing.md`, etc. — never a hardcoded `Color(...)`,
 * `.dp`, or `.sp` (specs/003-android-client.md §4.3).
 */
object FindlyTheme {
    val colors: FindlyColorTokens
        @Composable get() = LocalFindlyColors.current

    val typography
        @Composable get() = LocalFindlyTypography.current

    val spacing
        @Composable get() = LocalFindlySpacing.current

    val corner
        @Composable get() = LocalFindlyCorner.current

    val elevation
        @Composable get() = LocalFindlyElevation.current
}

/**
 * Provides the full design-token contract and additionally maps it onto a real Material3
 * [MaterialTheme] ([androidx.compose.material3.ColorScheme]/[Typography]/[Shapes]) so any
 * un-migrated Material3 primitive still themes correctly. Ships both light and dark token sets
 * from day one (specs/003 §4) — swapping either is a one-file change to
 * `ui/designsystem/token/ColorTokens.kt`, nothing else.
 */
@Composable
fun FindlyTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val tokens = if (darkTheme) DarkFindlyColors else LightFindlyColors

    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = tokens.primary,
            onPrimary = tokens.onPrimary,
            secondary = tokens.secondary,
            surface = tokens.surface,
            onSurface = tokens.onSurface,
            surfaceVariant = tokens.surfaceVariant,
            error = tokens.danger,
            onError = tokens.onDanger,
            outline = tokens.outline,
        )
    } else {
        lightColorScheme(
            primary = tokens.primary,
            onPrimary = tokens.onPrimary,
            secondary = tokens.secondary,
            surface = tokens.surface,
            onSurface = tokens.onSurface,
            surfaceVariant = tokens.surfaceVariant,
            error = tokens.danger,
            onError = tokens.onDanger,
            outline = tokens.outline,
        )
    }

    val materialTypography = Typography(
        displayLarge = FindlyTypography.displayLarge,
        titleLarge = FindlyTypography.titleLarge,
        titleMedium = FindlyTypography.titleMedium,
        bodyLarge = FindlyTypography.bodyLarge,
        bodyMedium = FindlyTypography.bodyMedium,
        labelSmall = FindlyTypography.labelSmall,
    )

    val shapes = Shapes(
        small = RoundedCornerShape(FindlyCorner.sm),
        medium = RoundedCornerShape(FindlyCorner.md),
        large = RoundedCornerShape(FindlyCorner.lg),
    )

    CompositionLocalProvider(
        LocalFindlyColors provides tokens,
        LocalFindlyTypography provides FindlyTypography,
        LocalFindlySpacing provides FindlySpacing,
        LocalFindlyCorner provides FindlyCorner,
        LocalFindlyElevation provides FindlyElevation,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = materialTypography,
            shapes = shapes,
            content = content,
        )
    }
}
