package com.findly.android.ui.designsystem.token

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

// Findly direction 2a — "Ember / Dusk"
// Ember layout, type, spacing and shape; Dusk colour values.

val LightFindlyColors = FindlyColors(
    primary        = Color(0xFF3A46C8),
    onPrimary      = Color(0xFFFFFFFF),
    secondary      = Color(0xFF0E7C8F),
    surface        = Color(0xFFF2F4FB),
    onSurface      = Color(0xFF10142A),
    surfaceVariant = Color(0xFFE2E6F5),
    danger         = Color(0xFFB3261E),
    onDanger       = Color(0xFFFFFFFF),
    success        = Color(0xFF10714A),
    warning        = Color(0xFF8A5A00),
    outline        = Color(0xFFA9B0CE),
)

val DarkFindlyColors = FindlyColors(
    primary        = Color(0xFF7C8BFF),
    onPrimary      = Color(0xFF0A0F27),
    secondary      = Color(0xFF4FE3D0),
    surface        = Color(0xFF0B0F1C),
    onSurface      = Color(0xFFE8ECF7),
    surfaceVariant = Color(0xFF161D33),
    danger         = Color(0xFFFF6B6B),
    onDanger       = Color(0xFF2A0708),
    success        = Color(0xFF52E39B),
    warning        = Color(0xFFFFC44D),
    outline        = Color(0xFF3A4463),
)

// Light `outline` is 2.1:1 — decorative hairlines only.
// Strokes that carry meaning use this instead (3.4:1).
val LightOutlineStrong = Color(0xFF6B739A)

// The online dot inside a `primary` marker bubble, both themes (5.4:1 on primary).
val MarkerOnlineDot = Color(0xFF52E39B)
val MarkerOnlineDotOn = Color(0xFF062418)

val FindlyShapes = Shapes(
    small      = RoundedCornerShape(12.dp),
    medium     = RoundedCornerShape(20.dp),
    large      = RoundedCornerShape(28.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

object FindlySpacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 20.dp
    val xl = 28.dp
    val xxl = 40.dp
}

object FindlyElevation {
    val level0 = 0.dp
    val level1 = 1.dp
    val level2 = 3.dp
    val level3 = 8.dp
}

// displayLarge 34/700/40/-0.4 · titleLarge 24/700/30/-0.2 · titleMedium 18/600/24/0
// bodyLarge 17/400/24/0 · bodyMedium 15/400/20/0 · labelSmall 12/700/16/+0.4 uppercase
