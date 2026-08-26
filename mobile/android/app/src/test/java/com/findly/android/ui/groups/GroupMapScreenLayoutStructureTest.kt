package com.findly.android.ui.groups

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §3.2/§10: `GroupMapScreen` "currently shares Android's
 * zero-height-roster bug" and "SHOULD ship inside the same task as the family map (same
 * components, same fix)" — see [com.findly.android.ui.map.MapScreenLayoutStructureTest]'s doc for
 * why this is a source-text test, not a rendering one (no Compose UI-test harness in this
 * module).
 */
class GroupMapScreenLayoutStructureTest {

    private val moduleRoot: File = locateModuleRoot()

    private fun locateModuleRoot(): File {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            if (File(dir, "src/main/java/com/findly/android/ui/groups/GroupMapScreen.kt").isFile) return dir
            dir = dir.parentFile
        }
        error("Could not locate the android app module root walking up from $cwd")
    }

    private val source: String by lazy {
        File(moduleRoot, "src/main/java/com/findly/android/ui/groups/GroupMapScreen.kt").readText()
    }

    @Test
    fun `GroupMapScreen's root container is a full-bleed Box, not an unweighted Column split`() {
        assertTrue(
            "expected the screen's root to be `Box(modifier = modifier.fillMaxSize())` — the map " +
                "and the FindlyBottomSheet roster must overlay each other, not compete for height " +
                "as two children of one unweighted Column (the exact bug this task fixes, shared " +
                "with the family map per 010 §3.2)",
            source.contains("Box(modifier = modifier.fillMaxSize())"),
        )
    }

    @Test
    fun `the map renderer fills the full-bleed Box, never an aspect-ratio card`() {
        val renderCallIndex = source.indexOf("mapRenderer.RenderGroup(")
        assertTrue("expected a mapRenderer.RenderGroup( call in GroupMapScreen.kt", renderCallIndex >= 0)

        val argsStart = renderCallIndex + "mapRenderer.RenderGroup(".length - 1
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
            "mapRenderer.RenderGroup(...)'s modifier must be Modifier.fillMaxSize() — full-bleed " +
                "per 010 §3.1/§3.2, never a fixed-aspect-ratio card",
            callArgs.contains("Modifier.fillMaxSize()"),
        )
    }

    @Test
    fun `the roster LazyColumn lives inside FindlyBottomSheet, not as a bare sibling of the map`() {
        val sheetOpen = source.indexOf("FindlyBottomSheet(")
        assertTrue("expected a FindlyBottomSheet( call in GroupMapScreen.kt", sheetOpen >= 0)

        val lazyColumnIndex = source.indexOf("LazyColumn(")
        assertTrue("expected a LazyColumn( call (the roster) in GroupMapScreen.kt", lazyColumnIndex >= 0)

        assertTrue(
            "the roster LazyColumn must be reached only after FindlyBottomSheet( opens — a " +
                "LazyColumn appearing before it would mean the roster is a bare top-level sibling " +
                "of the map again, the exact zero-height-roster regression this task fixes",
            lazyColumnIndex > sheetOpen,
        )
    }
}
