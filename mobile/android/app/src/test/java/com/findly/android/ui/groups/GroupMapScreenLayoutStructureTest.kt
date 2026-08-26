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

    /**
     * Review fix 2 — see [com.findly.android.ui.map.MapScreenLayoutStructureTest]'s matching test
     * doc for the full story: a plain `indexOf` ordering check is fooled by a bare roster call
     * reintroduced as a sibling of `FindlyBottomSheet` (demonstrated live and closed by walking
     * brace depth instead, mirroring `MainActivityInsetsStructureTest`); and the roster isn't
     * inlined at the `FindlyBottomSheet(...)` call site — it's rendered through a separate
     * private `GroupRosterList` composable, so the containment check is on that call, not on
     * `LazyColumn(` directly (which only appears inside `GroupRosterList`'s own body).
     */
    @Test
    fun `GroupRosterList is called only from inside FindlyBottomSheet's content lambda, never as a bare sibling of the map`() {
        val sheetOpen = source.indexOf("FindlyBottomSheet(")
        assertTrue("expected a FindlyBottomSheet( call in GroupMapScreen.kt", sheetOpen >= 0)

        val parenOpen = sheetOpen + "FindlyBottomSheet(".length - 1
        var parenDepth = 0
        var i = parenOpen
        do {
            when (source[i]) {
                '(' -> parenDepth++
                ')' -> parenDepth--
            }
            i++
        } while (parenDepth > 0 && i < source.length)

        val contentLambdaOpen = source.indexOf("{", startIndex = i)
        assertTrue(
            "expected FindlyBottomSheet(...) to be followed by a trailing content lambda `{ ... }`",
            contentLambdaOpen >= 0,
        )

        var braceDepth = 1
        var j = contentLambdaOpen + 1
        while (braceDepth > 0 && j < source.length) {
            when (source[j]) {
                '{' -> braceDepth++
                '}' -> braceDepth--
            }
            j++
        }
        val contentLambdaClose = j - 1

        // Excludes the `private fun GroupRosterList(` declaration itself, further down the file
        // — `indexOf("GroupRosterList(")` matches that text too, and it is not a call site.
        val rosterListCalls = buildList {
            var searchFrom = 0
            while (true) {
                val found = source.indexOf("GroupRosterList(", searchFrom)
                if (found < 0) break
                val isDeclaration = source.substring(maxOf(0, found - 4), found) == "fun "
                if (!isDeclaration) add(found)
                searchFrom = found + 1
            }
        }
        assertTrue("expected at least one GroupRosterList( call (the roster) in GroupMapScreen.kt", rosterListCalls.isNotEmpty())

        rosterListCalls.forEach { callIndex ->
            assertTrue(
                "found a GroupRosterList( call at index $callIndex outside FindlyBottomSheet's " +
                    "content lambda (open=$contentLambdaOpen, close=$contentLambdaClose) — the " +
                    "roster anywhere outside the sheet's content slot is a bare sibling of the " +
                    "map again, the exact zero-height-roster regression this task fixes",
                callIndex in contentLambdaOpen..contentLambdaClose,
            )
        }
    }

    @Test
    fun `GroupRosterList's own body actually renders a LazyColumn`() {
        val defIndex = source.indexOf("private fun GroupRosterList(")
        assertTrue("expected a private fun GroupRosterList( definition in GroupMapScreen.kt", defIndex >= 0)

        val bodyOpen = source.indexOf("{", startIndex = defIndex)
        assertTrue("expected GroupRosterList(...) to have a function body", bodyOpen >= 0)

        var depth = 1
        var k = bodyOpen + 1
        while (depth > 0 && k < source.length) {
            when (source[k]) {
                '{' -> depth++
                '}' -> depth--
            }
            k++
        }
        val bodyClose = k - 1

        val lazyColumnIndex = source.indexOf("LazyColumn(", startIndex = bodyOpen)
        assertTrue(
            "expected GroupRosterList's body to contain a LazyColumn( call — this is what " +
                "actually backs the roster once it's confirmed reachable only through " +
                "FindlyBottomSheet",
            lazyColumnIndex in bodyOpen..bodyClose,
        )
    }
}
