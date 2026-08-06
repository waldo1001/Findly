package com.findly.android.ui.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Surface
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
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
 *
 * A32: also paints the backdrop itself with a [Surface] coloured from `tokens.surface`, so the
 * screen background is token-driven rather than inherited from the *window* background
 * (`res/values{,-night}/themes.xml`). Before this, `content` sat directly under [MaterialTheme]
 * with nothing painting a background, so every screen's backdrop was whatever the XML window
 * theme happened to be — permanently light pre-A32, since there was no `values-night` variant
 * either. Dark tokens (e.g. near-white `onSurface` #E8ECF7) were then flipped correctly by
 * Compose while the backdrop stayed light, an unreadable combination the contrast suite cannot
 * catch because it only asserts token-vs-token, never token-vs-window. This is the durable half
 * of the fix: it makes the Compose layer self-sufficient regardless of what the window theme
 * does, so the window theme only has to be right for the brief pre-Compose splash frame.
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
        ) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = tokens.surface,
                contentColor = tokens.onSurface,
                content = content,
            )
        }
    }
}
