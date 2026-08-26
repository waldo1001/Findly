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

    /**
     * Review fix 2: a plain `indexOf` ordering check (`lazyColumnIndex > sheetOpen`) only ever
     * looks at the *first* `LazyColumn(` match in the whole file. It is fooled by a bare roster
     * call reintroduced as a **sibling of** `FindlyBottomSheet` (not nested inside it) — as long
     * as the sibling sits textually after the sheet call, the weak check never even looks at it.
     * Demonstrated live: adding `LazyColumn(modifier = Modifier.fillMaxWidth()) {}` as a sibling
     * right after `FindlyBottomSheet(...)` closes left the old ordering-only version of this test
     * green.
     *
     * **Correction during the fix:** the roster isn't inlined at the `FindlyBottomSheet(...)`
     * call site at all — it's rendered through a separate private `RosterList` composable, called
     * from the sheet's content lambda (`RosterList(` at the call site; `LazyColumn(` only appears
     * later, inside `RosterList`'s own function body). Walking brace depth from the content
     * lambda looking for `LazyColumn(` directly is therefore the wrong containment check for
     * *this* codebase's structure — it fails even against the correct, unmodified source, because
     * the literal text it's hunting for lives in a different function entirely. The actual
     * regression surface is the **call site**: this asserts `RosterList(` — whatever it renders
     * internally — is reached only from inside `FindlyBottomSheet`'s trailing content lambda,
     * mirroring `MainActivityInsetsStructureTest`'s own brace-depth containment technique (locate
     * the lambda's own opening/closing braces by walking paren depth past the call's argument
     * list, then brace depth, and require the target call to fall strictly between the two).
     */
    @Test
    fun `RosterList is called only from inside FindlyBottomSheet's content lambda, never as a bare sibling of the map`() {
        val sheetOpen = source.indexOf("FindlyBottomSheet(")
        assertTrue("expected a FindlyBottomSheet( call in MapScreen.kt", sheetOpen >= 0)

        // Walk paren depth from the call's own opening "(" to its matching close — this skips
        // over the nested `header = { ... }` lambda's own braces too, since only '(' / ')'
        // change depth here, landing just past the call's whole argument list.
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
        val contentLambdaClose = j - 1 // index of the matching '}'

        // Excludes the `private fun RosterList(` declaration itself, further down the file —
        // `indexOf("RosterList(")` matches that text too, and it is not a call site.
        val rosterListCalls = buildList {
            var searchFrom = 0
            while (true) {
                val found = source.indexOf("RosterList(", searchFrom)
                if (found < 0) break
                val isDeclaration = source.substring(maxOf(0, found - 4), found) == "fun "
                if (!isDeclaration) add(found)
                searchFrom = found + 1
            }
        }
        assertTrue("expected at least one RosterList( call (the roster) in MapScreen.kt", rosterListCalls.isNotEmpty())

        rosterListCalls.forEach { callIndex ->
            assertTrue(
                "found a RosterList( call at index $callIndex outside FindlyBottomSheet's " +
                    "content lambda (open=$contentLambdaOpen, close=$contentLambdaClose) — the " +
                    "roster anywhere outside the sheet's content slot is a bare sibling of the " +
                    "map again, the exact zero-height-roster regression this task fixes",
                callIndex in contentLambdaOpen..contentLambdaClose,
            )
        }
    }

    @Test
    fun `RosterList's own body actually renders a LazyColumn`() {
        val defIndex = source.indexOf("private fun RosterList(")
        assertTrue("expected a private fun RosterList( definition in MapScreen.kt", defIndex >= 0)

        val bodyOpen = source.indexOf("{", startIndex = defIndex)
        assertTrue("expected RosterList(...) to have a function body", bodyOpen >= 0)

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
            "expected RosterList's body to contain a LazyColumn( call — this is what actually " +
                "backs the roster once it's confirmed reachable only through FindlyBottomSheet",
            lazyColumnIndex in bodyOpen..bodyClose,
        )
    }
}
