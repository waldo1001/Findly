// Findly — Android color tokens
// Drop into ui/designsystem/token/. Nothing outside DesignSystem should reference raw Color(...).

val LightFindlyColors = FindlyColors(
    primary        = Color(0xFF00696E),
    onPrimary      = Color(0xFFFFFFFF),
    secondary      = Color(0xFF4C5FD5),
    surface        = Color(0xFFFAFAF7),
    onSurface      = Color(0xFF1B1D1C),
    surfaceVariant = Color(0xFFEEEEE9),
    danger         = Color(0xFFC0362C),
    onDanger       = Color(0xFFFFFFFF),
    success        = Color(0xFF1E7D46),
    warning        = Color(0xFF8A5A00),
    outline        = Color(0xFFC9C8C2),
)

val DarkFindlyColors = FindlyColors(
    primary        = Color(0xFF4CD4D9),
    onPrimary      = Color(0xFF00312F),
    secondary      = Color(0xFFA9B4FF),
    surface        = Color(0xFF17181A),
    onSurface      = Color(0xFFECECE6),
    surfaceVariant = Color(0xFF24262A),
    danger         = Color(0xFFF2867B),
    onDanger       = Color(0xFF490A05),
    success        = Color(0xFF5FD08A),
    warning        = Color(0xFFE4B44C),
    outline        = Color(0xFF3A3D42),
)

// Typography (sp), spacing/corner (dp), elevation (dp) — unified values
val FindlyTypography = FindlyTypeScale(
    displayLarge = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold,     lineHeight = 40.sp, letterSpacing = (-0.68).sp),
    titleLarge   = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, lineHeight = 28.sp, letterSpacing = (-0.22).sp),
    titleMedium  = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp),
    bodyLarge    = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Normal,   lineHeight = 24.sp),
    bodyMedium   = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Normal,   lineHeight = 20.sp),
    labelSmall   = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium,   lineHeight = 16.sp, letterSpacing = 0.4.sp),
)

val FindlySpacing = FindlySpacingScale(xs = 4.dp, sm = 8.dp, md = 12.dp, lg = 16.dp, xl = 24.dp, xxl = 32.dp)

val FindlyCorners = FindlyCornerScale(sm = 8.dp, md = 12.dp, lg = 20.dp, pill = 999.dp)

val FindlyElevation = FindlyElevationScale(level0 = 0.dp, level1 = 1.dp, level2 = 3.dp, level3 = 6.dp)
