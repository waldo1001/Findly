package com.findly.android.ui.map

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §3.6 (A55) — the lifecycle wiring is the one part of the
 * map's data-freshness behavior no JVM unit test can exercise (there is no Compose UI-test harness
 * in this module, 003 §4/§14), and it is also the part whose silent loss would quietly revert the
 * whole feature: the policy (`MapRefreshController`) and the holders keep passing their tests with
 * no screen ever calling `onVisible()`. So — the `MapScreenLayoutStructureTest` /
 * `MainActivityInsetsStructureTest` precedent — assert the structural property in source text: each
 * map route reports visibility through a `LifecycleResumeEffect` (RESUMED on a `NavBackStackEntry`
 * == the destination is on top **and** the activity is resumed == "visible and foregrounded"), and
 * each view model forwards both calls to its state holder.
 */
class MapRefreshWiringStructureTest {

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

    private fun source(relative: String): String =
        File(moduleRoot, "src/main/java/com/findly/android/$relative").readText()

    /** The text of `fun <name>(...) { ... }`'s body: paren depth past the (default-lambda-laden)
     * parameter list first, then brace depth from the body's own opening brace. */
    private fun functionBody(source: String, signaturePrefix: String): String {
        val start = source.indexOf(signaturePrefix)
        assertTrue("expected `$signaturePrefix` in the source", start >= 0)
        var i = start + signaturePrefix.length - 1
        var parenDepth = 0
        do {
            when (source[i]) {
                '(' -> parenDepth++
                ')' -> parenDepth--
            }
            i++
        } while (parenDepth > 0 && i < source.length)
        val open = source.indexOf('{', startIndex = i)
        var depth = 1
        var j = open + 1
        while (depth > 0 && j < source.length) {
            when (source[j]) {
                '{' -> depth++
                '}' -> depth--
            }
            j++
        }
        return source.substring(open, j)
    }

    private fun assertReportsVisibility(routeBody: String, route: String) {
        assertTrue(
            "$route must wrap its visibility reporting in `LifecycleResumeEffect(viewModel)` " +
                "(010 §3.6: RESUMED on the destination's entry == visible and foregrounded)",
            routeBody.contains("LifecycleResumeEffect(viewModel)"),
        )
        assertTrue("$route must call viewModel.onVisible() when resumed", routeBody.contains("viewModel.onVisible()"))
        assertTrue(
            "$route must call viewModel.onHidden() from onPauseOrDispose — that is what stops the " +
                "30 s timer, so nothing is ever fetched in the background (010 §3.6)",
            routeBody.contains("onPauseOrDispose { viewModel.onHidden() }"),
        )
    }

    @Test
    fun `MapRoute reports visibility through a LifecycleResumeEffect`() {
        assertReportsVisibility(functionBody(source("ui/map/MapScreen.kt"), "fun MapRoute("), "MapRoute")
    }

    @Test
    fun `GroupMapRoute reports visibility through a LifecycleResumeEffect`() {
        assertReportsVisibility(functionBody(source("ui/groups/GroupMapScreen.kt"), "fun GroupMapRoute("), "GroupMapRoute")
    }

    @Test
    fun `MapViewModel and GroupMapViewModel forward onVisible and onHidden to their state holders`() {
        listOf("ui/map/MapViewModel.kt", "ui/groups/GroupMapViewModel.kt").forEach { file ->
            val text = source(file)
            assertTrue("$file must forward onVisible()", text.contains("fun onVisible() = stateHolder.onVisible()"))
            assertTrue("$file must forward onHidden()", text.contains("fun onHidden() = stateHolder.onHidden()"))
        }
    }

    @Test
    fun `both state holders delegate their trigger policy to MapRefreshController instead of polling themselves`() {
        listOf("ui/map/MapStateHolder.kt", "ui/groups/GroupMapStateHolder.kt").forEach { file ->
            val text = source(file)
            assertTrue("$file must build a MapRefreshController", text.contains("MapRefreshController("))
            assertTrue("$file must start it from init (first appearance)", text.contains("refreshController.start()"))
            assertTrue("$file must not run its own delay-based poll loop", !text.contains("delay("))
        }
    }
}
