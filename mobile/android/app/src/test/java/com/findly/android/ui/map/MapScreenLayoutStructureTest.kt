package com.findly.android.ui.map

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §10: "the Android `Column`-starvation bug's fix is pinned
 * by a structure test where feasible (the `MainActivityInsetsStructureTest` precedent)". The bug
 * (specs/010 §3, A12-vintage): `MapScreen.kt` put a `fillMaxSize()` map renderer and a roster
 * `LazyColumn` as two children of one **unweighted** `Column` — the map ate all the height, the
 * roster below it laid out at zero height, invisible since A12 shipped. There is no Compose
 * UI-test harness in this module (`MainActivityInsetsStructureTest`'s doc explains why this is a
 * source-text test, not a rendering one), so this asserts the structural property whose absence
 * caused the regression: the screen's root is a `Box` (map and roster overlaid, not two `Column`
 * siblings competing for height), the map renderer fills that `Box`, and the roster's `LazyColumn`
 * is nested inside `FindlyBottomSheet`, never a bare top-level sibling of the map again.
 */
class MapScreenLayoutStructureTest {

    private val moduleRoot: File = locateModuleRoot()

    private fun locateModuleRoot(): File {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            if (File(dir, "src/main/java/com/findly/android/ui/map/MapScreen.kt").isFile) return dir
            dir = dir.parentFile
        }
        error("Could not locate the android app module root walking up from $cwd")
    }

    private val source: String by lazy {
        File(moduleRoot, "src/main/java/com/findly/android/ui/map/MapScreen.kt").readText()
    }

    @Test
    fun `MapScreen's root container is a full-bleed Box, not an unweighted Column split`() {
        assertTrue(
            "expected the screen's root to be `Box(modifier = modifier.fillMaxSize())` — the map " +
                "and the FindlyBottomSheet roster must overlay each other, not compete for height " +
                "as two children of one unweighted Column (the exact bug this task fixes)",
            source.contains("Box(modifier = modifier.fillMaxSize())"),
        )
    }

    @Test
    fun `the map renderer fills the full-bleed Box, never an aspect-ratio card`() {
        val renderCallIndex = source.indexOf("mapRenderer.Render(")
        assertTrue("expected a mapRenderer.Render( call in MapScreen.kt", renderCallIndex >= 0)

        // Walk paren depth from the call's own opening "(" to find its matching close, so the
        // assertion below only looks at THIS call's own argument list.
        val argsStart = renderCallIndex + "mapRenderer.Render(".length - 1
        var depth = 0
        var index = argsStart
        do {
            when (source[index]) {
                '(' -> depth++
                ')' -> depth--
            }
            index++
        } while (depth > 0 && index < source.length)
        val callArgs = source.substring(argsStart, index)

        assertTrue(
            "mapRenderer.Render(...)'s modifier must be Modifier.fillMaxSize() — full-bleed per " +
                "010 §3.1, never a fixed-aspect-ratio card",
            callArgs.contains("Modifier.fillMaxSize()"),
        )
    }

    @Test
    fun `the roster LazyColumn lives inside FindlyBottomSheet, not as a bare sibling of the map`() {
        val sheetOpen = source.indexOf("FindlyBottomSheet(")
        assertTrue("expected a FindlyBottomSheet( call in MapScreen.kt", sheetOpen >= 0)

        val lazyColumnIndex = source.indexOf("LazyColumn(")
        assertTrue("expected a LazyColumn( call (the roster) in MapScreen.kt", lazyColumnIndex >= 0)

        assertTrue(
            "the roster LazyColumn must be reached only after FindlyBottomSheet( opens — a " +
                "LazyColumn appearing before it would mean the roster is a bare top-level sibling " +
                "of the map again, the exact zero-height-roster regression this task fixes",
            lazyColumnIndex > sheetOpen,
        )
    }
}
