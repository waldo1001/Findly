package com.findly.android.ui.designsystem

import androidx.compose.ui.graphics.Color
import com.findly.android.ui.designsystem.token.DarkFindlyColors
import com.findly.android.ui.designsystem.token.LightFindlyColors
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A32 regression guard for cause #1 of the dark-mode-renders-half-light bug
 * (docs/implementation-handoff.md's A32 row; specs/003-android-client.md §4.1): the manifest-level
 * window theme (`res/values/themes.xml`) was hardcoded to
 * `android:Theme.Material.Light.NoActionBar` with **no `res/values-night/` variant at all**, so the
 * pre-Compose window background stayed light even when the system was in dark mode. This is the
 * only automated guard that class of regression can realistically get:
 *
 * - The contrast suite (`ContrastTest`/equivalent) asserts `onSurface` against the `surface`
 *   *token* and has no way to know the window renders something else — that blind spot is exactly
 *   what let A32 ship in the first place.
 * - There is no Compose UI-test harness in this module (no Robolectric, no
 *   `androidx.compose.ui.test`, no `androidTest` source set at all — see `app/build.gradle.kts`),
 *   so nothing here can render an actual `Activity`/`Window` and sample its background pixel the
 *   way the manual emulator verification in the A32 dev-loop report did. Asserting a Kotlin token
 *   value would prove nothing about the window and would pass even if `values-night/` were deleted
 *   again — the same dishonest-test failure mode this project has already been burned by once.
 *
 * What this test CAN honestly do: read the actual XML resource files that shipped the bug and
 * assert the two properties whose absence caused it — a night variant exists, and its platform
 * parent is the dark one, not light. It also pins `android:windowBackground` in both variants
 * against the **real** `LightFindlyColors.surface` / `DarkFindlyColors.surface` values
 * (`ui/designsystem/token/ColorTokens.kt`) — not a second hand-copied literal — by reading the
 * actual `Color`'s `red`/`green`/`blue`/`alpha` components and deriving the `#AARRGGBB` string a
 * plain-JVM test would compare against, the same "reference the real token, don't restate it"
 * pattern `ColorTokenContrastTest`/`ContrastRatio.kt` already establish for this module (no
 * Robolectric or Android runtime needed — `Color`'s channel accessors are pure Kotlin on the JVM).
 * That closes the actual drift path this guards against: change a `surface` token and forget the
 * XML (or vice versa) and this test fails, because it is the token driving the expectation, not a
 * second copy of the hex. It does NOT prove Compose actually paints correctly at runtime
 * (`FindlyTheme`'s `Surface(color = colors.surface)` is the other, durable half of the A32 fix,
 * and that half genuinely has no automated guard — verified manually only, see the A32 report and
 * the comment on that `Surface` call in `FindlyTheme.kt`).
 */
class WindowThemeDayNightTest {

    private val moduleRoot: File = locateModuleRoot()

    private fun locateModuleRoot(): File {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            if (File(dir, "src/main/res/values/themes.xml").isFile) return dir
            dir = dir.parentFile
        }
        error(
            "Could not locate the android app module root (looked for src/main/res/values/themes.xml " +
                "walking up from $cwd) — this test reads real resource files, not classpath resources.",
        )
    }

    private fun readThemesXml(variant: String): String {
        val file = File(moduleRoot, "src/main/res/$variant/themes.xml")
        assertTrue("expected ${file.path} to exist", file.isFile)
        return file.readText()
    }

    /**
     * The actual `Color` -> `#AARRGGBB` string an `android:windowBackground` XML attribute would
     * need to equal to resolve to the same colour. Derived from `color`'s own `red`/`green`/
     * `blue`/`alpha` (Float 0f..1f) components — no Android/Robolectric runtime required, same as
     * `ContrastRatio.kt`'s `relativeLuminance`. This is the actual token value, not a restated
     * literal, so a token change with no matching XML change makes the comparison in
     * `windowBackground is pinned to the real surface token hex in both themes` fail.
     */
    private fun argbHex(color: Color): String {
        fun channel(v: Float) = Math.round(v.coerceIn(0f, 1f) * 255f)
        return "#%02X%02X%02X%02X".format(channel(color.alpha), channel(color.red), channel(color.green), channel(color.blue))
    }

    @Test
    fun `a values-night theme variant exists`() {
        val nightFile = File(moduleRoot, "src/main/res/values-night/themes.xml")
        assertTrue(
            "res/values-night/themes.xml is missing — this is exactly A32's cause #1: with no " +
                "night variant, the window theme is permanently the light one regardless of system " +
                "dark mode",
            nightFile.isFile,
        )
    }

    @Test
    fun `light window theme uses the light platform parent`() {
        val light = readThemesXml("values")
        assertTrue(
            "light Theme.Findly should parent off the light platform theme",
            light.contains("android:Theme.Material.Light.NoActionBar"),
        )
    }

    @Test
    fun `night window theme uses the dark platform parent, not the light one`() {
        val night = readThemesXml("values-night")
        assertTrue(
            "night Theme.Findly should parent off the DARK platform theme (android:Theme.Material" +
                ".NoActionBar) — reusing the light parent here would reproduce A32 even with the " +
                "file present",
            night.contains("android:Theme.Material.NoActionBar"),
        )
        assertTrue(
            "night Theme.Findly's parent must not be the light variant",
            !night.contains("android:Theme.Material.Light.NoActionBar"),
        )
    }

    @Test
    fun `windowBackground is pinned to the real surface token hex in both themes`() {
        val light = readThemesXml("values")
        val night = readThemesXml("values-night")

        // Derived from the ACTUAL FindlyColorTokens.surface Color values
        // (ui/designsystem/token/ColorTokens.kt), not a second hand-copied literal — change
        // LightFindlyColors.surface or DarkFindlyColors.surface without touching the matching
        // themes.xml and these two assertions fail, which is the entire point of this test.
        val lightSurfaceArgb = argbHex(LightFindlyColors.surface)
        val darkSurfaceArgb = argbHex(DarkFindlyColors.surface)

        assertTrue(
            "light windowBackground should be pinned to LightFindlyColors.surface " +
                "($lightSurfaceArgb) — either the XML fell out of sync with the token, or the " +
                "token changed and values/themes.xml needs updating to match",
            light.contains(lightSurfaceArgb),
        )
        assertTrue(
            "night windowBackground should be pinned to DarkFindlyColors.surface " +
                "($darkSurfaceArgb) — either the XML fell out of sync with the token, or the " +
                "token changed and values-night/themes.xml needs updating to match",
            night.contains(darkSurfaceArgb),
        )
        assertNotEquals(
            "light and dark surface tokens must not resolve to the same colour",
            lightSurfaceArgb,
            darkSurfaceArgb,
        )
    }

    @Test
    fun `both variants declare the same style name so the manifest reference resolves either way`() {
        val light = readThemesXml("values")
        val night = readThemesXml("values-night")
        assertEquals(
            "both files must declare Theme.Findly (the name AndroidManifest.xml references) or " +
                "the night variant silently falls back to the light one",
            true,
            light.contains("name=\"Theme.Findly\"") && night.contains("name=\"Theme.Findly\""),
        )
    }
}
