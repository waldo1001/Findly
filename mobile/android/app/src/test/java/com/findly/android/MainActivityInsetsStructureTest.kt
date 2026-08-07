package com.findly.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A25 (specs/009-device-runtime.md §7, specs/003-android-client.md §11) regression guard for the
 * denial-banner-over-the-status-bar defect: `FindlyPermissionBanner` rendered on the first screen
 * every user sees, and a fresh emulator run (2026-08-06) showed its title sitting behind the system
 * clock with its own top edge inside the status bar's tap region.
 *
 * **Why this is a source-text test, not a rendering one.** There is no Compose UI-test harness in
 * this module — no Robolectric, no `androidx.compose.ui.test`, no `androidTest` source set at all
 * (`WindowThemeDayNightTest`'s doc; `app/build.gradle.kts`) — so nothing here can actually inflate
 * `MainActivity`'s `Window` and sample where the banner paints, the way the fix was verified
 * manually on a real emulator for A23's back-chevron fix and would need to be here too. What this
 * test CAN do, honestly, is what `WindowThemeDayNightTest` already established the precedent for:
 * read the real source file and assert the structural property whose absence caused the regression
 * class, so a future edit that reintroduces it fails loudly instead of silently.
 *
 * Two properties, both required:
 * 1. The root `Box` inset modifier chain covers `statusBarsPadding()`, `displayCutoutPadding()`
 *    (added by A25 — the one system-UI region `statusBarsPadding()` alone does not cover, called
 *    out explicitly in A25's task text), and `navigationBarsPadding()`.
 * 2. `FindlyPermissionBanner(` is called **inside** that `Box`'s content lambda, not as a sibling
 *    rendered outside it — tracked via brace depth from the `Box(` open to its matching close,
 *    exactly the "renders above that padded root" failure mode A25 describes.
 */
class MainActivityInsetsStructureTest {

    private val moduleRoot: File = locateModuleRoot()

    private fun locateModuleRoot(): File {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            if (File(dir, "src/main/java/com/findly/android/MainActivity.kt").isFile) return dir
            dir = dir.parentFile
        }
        error(
            "Could not locate the android app module root (looked for " +
                "src/main/java/com/findly/android/MainActivity.kt walking up from $cwd) — this " +
                "test reads the real source file, not a classpath resource.",
        )
    }

    private val source: String by lazy {
        File(moduleRoot, "src/main/java/com/findly/android/MainActivity.kt").readText()
    }

    /** The line that opens the root inset `Box` — anchors both assertions below to the same call. */
    private fun rootBoxOpenIndex(): Int {
        val index = source.indexOf("Box(")
        assertTrue("expected a Box( call in MainActivity.kt", index >= 0)
        return index
    }

    @Test
    fun `the root Box applies status-bar, display-cutout, and navigation-bar padding`() {
        val boxOpen = rootBoxOpenIndex()
        // The modifier chain is written across the next few lines, up to the closing ") {" of the
        // Box call itself — bounded by the first "{" after "Box(" so a later, unrelated Box() call
        // elsewhere in the file (there is none today, but this keeps the test from silently
        // matching the wrong one) can't be picked up instead.
        val contentStart = source.indexOf("{", startIndex = boxOpen)
        val modifierChain = source.substring(boxOpen, contentStart)

        assertTrue(
            "root Box is missing statusBarsPadding() — without it, content (including the " +
                "degraded-state banner) renders under the system status bar",
            modifierChain.contains("statusBarsPadding()"),
        )
        assertTrue(
            "root Box is missing displayCutoutPadding() (A25) — statusBarsPadding() alone does " +
                "not cover a display cutout that extends beyond the reported status-bar height",
            modifierChain.contains("displayCutoutPadding()"),
        )
        assertTrue(
            "root Box is missing navigationBarsPadding() — without it, content renders under the " +
                "system navigation bar",
            modifierChain.contains("navigationBarsPadding()"),
        )
    }

    @Test
    fun `FindlyPermissionBanner is rendered inside the inset-padded root Box, not above it`() {
        val boxOpen = rootBoxOpenIndex()
        val contentStart = source.indexOf("{", startIndex = boxOpen)
        assertTrue("could not find the root Box's content lambda opening brace", contentStart >= 0)

        val bannerCallIndex = source.indexOf("FindlyPermissionBanner(")
        assertTrue("expected a FindlyPermissionBanner( call in MainActivity.kt", bannerCallIndex >= 0)
        assertTrue(
            "FindlyPermissionBanner is called before the inset-padded root Box even opens — it " +
                "cannot inherit statusBarsPadding()/displayCutoutPadding()/navigationBarsPadding() " +
                "from a Box it isn't inside",
            bannerCallIndex > contentStart,
        )

        // Walk brace depth from the Box's own opening "{" and confirm we have not returned to
        // depth 0 (i.e. closed the Box) by the time FindlyPermissionBanner( is reached — this is
        // exactly A25's "the banner renders above that padded root" failure mode: a banner call
        // placed as a sibling AFTER the Box closes would still satisfy the `indexOf` check above
        // (it comes later in the file) while no longer being inside it.
        var depth = 0
        var index = contentStart
        while (index < bannerCallIndex) {
            when (source[index]) {
                '{' -> depth++
                '}' -> depth--
            }
            index++
        }
        assertTrue(
            "FindlyPermissionBanner is called after the root Box has already closed (brace depth " +
                "$depth relative to its content lambda) — it renders as a sibling outside the " +
                "inset-padded root, not a child of it, so it would not be covered by " +
                "statusBarsPadding()/displayCutoutPadding()/navigationBarsPadding()",
            depth > 0,
        )
    }
}
