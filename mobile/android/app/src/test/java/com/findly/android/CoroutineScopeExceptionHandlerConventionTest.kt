package com.findly.android

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A42 (docs/implementation-handoff.md) regression guard for the process-killing defect class found
 * three consecutive tasks in a row (A39/A40/A41's reviews): a [kotlinx.coroutines.CoroutineScope]
 * built without a [kotlinx.coroutines.CoroutineExceptionHandler] lets *any* uncaught throw from
 * *any* `launch` on it reach the default handler and kill the whole process —
 * [kotlinx.coroutines.SupervisorJob] does **not** help, it isolates sibling coroutines from each
 * other's failures, it does not swallow exceptions.
 *
 * **Why this is a source-text test, not a Detekt/lint rule.** A custom Detekt rule needs its own
 * Gradle subproject wired against `detekt-api`, a rule-testing harness, and version-pairing upkeep
 * against this module's Kotlin/AGP versions — real, ongoing tooling weight for a one-developer
 * project that has already deliberately declined a Compose UI test harness rather than carry it
 * (backlog A38). `MainActivityInsetsStructureTest`/`WindowThemeDayNightTest` already established
 * the cheaper precedent this test follows instead: read the real source files and assert the
 * structural property whose absence caused the regression class, using the JUnit/Kotlin-only
 * toolchain this module already runs on every `./gradlew test`. It runs on **every** production
 * source file under `src/main`, not just the four sites named in A42's task brief, so a *new*
 * `CoroutineScope(` construction site added later without a handler fails this test immediately
 * instead of waiting for a fourth review to catch it by hand.
 *
 * Two properties, both required of every real `CoroutineScope(` construction site (comments are
 * stripped first so a doc comment merely *mentioning* `CoroutineScope(` — several files here do,
 * describing exactly this bug — can never itself trip the assertion; `rememberCoroutineScope()`
 * calls are Compose's own scope, tied to composition lifecycle rather than a raw construction, and
 * are excluded by the same word-boundary the regex uses):
 *
 * 1. The constructor call's argument list carries a [kotlinx.coroutines.CoroutineExceptionHandler]
 *    — inline, or by reference to a named `val` — never a bare `SupervisorJob() + Dispatchers.X`.
 * 2. Where that handler logs, it logs the throwable's class name only (specs/009-device-runtime.md
 *    §9: "Never log coordinates, `deviceId`, phone numbers, or tokens... Counts and error codes
 *    only") — never the throwable/exception object itself, whose `message` can embed exactly that
 *    forbidden payload (a location or Retrofit exception's message routinely does).
 */
class CoroutineScopeExceptionHandlerConventionTest {

    private val moduleRoot: File = locateModuleRoot()

    private fun locateModuleRoot(): File {
        val cwd = File(System.getProperty("user.dir") ?: ".").absoluteFile
        var dir: File? = cwd
        while (dir != null) {
            if (File(dir, "src/main/java/com/findly/android/AppContainer.kt").isFile) return dir
            dir = dir.parentFile
        }
        error(
            "Could not locate the android app module root (looked for " +
                "src/main/java/com/findly/android/AppContainer.kt walking up from $cwd) — this " +
                "test reads the real source tree, not a classpath resource.",
        )
    }

    private val mainSourceRoot: File
        get() = File(moduleRoot, "src/main/java")

    private fun kotlinSourceFiles(): List<File> =
        mainSourceRoot.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    /** Strips `/* ... */` and `// ...` comments so a doc comment that merely *mentions*
     * `CoroutineScope(`/`CoroutineExceptionHandler` in prose (several files here do, describing
     * this very defect class) can never masquerade as — or hide — real code below. */
    private fun stripComments(source: String): String {
        val noBlockComments = Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL).replace(source, "")
        return Regex("//[^\n]*").replace(noBlockComments, "")
    }

    /** Every real `CoroutineScope(` construction — not `rememberCoroutineScope()`, excluded by the
     * negative lookbehind requiring a non-letter (or start of file) immediately before the match —
     * as the full text between (and including) its balanced parentheses. */
    private fun constructionSites(source: String): List<String> {
        val regex = Regex("(?<![A-Za-z])CoroutineScope\\(")
        return regex.findAll(source).map { match ->
            val openParen = match.range.last
            var depth = 1
            var i = openParen + 1
            while (i < source.length && depth > 0) {
                when (source[i]) {
                    '(' -> depth++
                    ')' -> depth--
                }
                i++
            }
            source.substring(openParen, i)
        }.toList()
    }

    @Test
    fun `every CoroutineScope construction site carries a CoroutineExceptionHandler`() {
        val failures = mutableListOf<String>()
        for (file in kotlinSourceFiles()) {
            val source = stripComments(file.readText())
            for (site in constructionSites(source)) {
                if (!site.contains("exceptionhandler", ignoreCase = true)) {
                    failures += "${file.relativeTo(mainSourceRoot)}: $site"
                }
            }
        }
        assertTrue(
            "Found CoroutineScope( construction site(s) with no CoroutineExceptionHandler. A " +
                "SupervisorJob does NOT swallow exceptions - it only isolates sibling coroutines " +
                "from each other's failures - so any uncaught throw from any launch{} on one of " +
                "these scopes reaches the default handler and kills the whole process (A39/A40/A41 " +
                "found this three times running). Add a CoroutineExceptionHandler that logs the " +
                "exception's class name only:\n" + failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }

    /** The two real handlers in this module both use the `{ _, throwable -> ... }` shape; captures
     * the throwable parameter's name so the check works even if a future handler renames it. */
    private val handlerRegex = Regex("""CoroutineExceptionHandler\s*\{\s*\w+\s*,\s*(\w+)\s*->""")

    private fun handlerBodies(source: String): List<Pair<String, String>> {
        val results = mutableListOf<Pair<String, String>>()
        for (match in handlerRegex.findAll(source)) {
            val throwableName = match.groupValues[1]
            var depth = 1
            var i = match.range.last + 1
            while (i < source.length && depth > 0) {
                when (source[i]) {
                    '{' -> depth++
                    '}' -> depth--
                }
                i++
            }
            val body = source.substring(match.range.last + 1, i - 1)
            results += throwableName to body
        }
        return results
    }

    @Test
    fun `every CoroutineExceptionHandler logs the throwable's class name only, never the throwable itself`() {
        val failures = mutableListOf<String>()
        for (file in kotlinSourceFiles()) {
            val source = stripComments(file.readText())
            for ((throwableName, body) in handlerBodies(source)) {
                val classNameUsage = Regex("""\b${Regex.escape(throwableName)}\s*::\s*class\s*\.\s*simpleName""")
                if (!classNameUsage.containsMatchIn(body)) {
                    failures += "${file.relativeTo(mainSourceRoot)}: handler for `$throwableName` " +
                        "never logs `$throwableName::class.simpleName` — specs/009 §9 permits " +
                        "error codes/class names only, never the message"
                    continue
                }
                // Every other bare mention of the throwable identifier (i.e. not part of the
                // `::class.simpleName` access just verified above) means it is being passed/used
                // some other way - e.g. `Log.w(TAG, "...", throwable)`, which logs the full
                // message/stacktrace and can leak coordinates/deviceId/tokens (specs/009 §9).
                val withClassNameUsagesRemoved = classNameUsage.replace(body, "")
                val bareUsage = Regex("""\b${Regex.escape(throwableName)}\b""")
                if (bareUsage.containsMatchIn(withClassNameUsagesRemoved)) {
                    failures += "${file.relativeTo(mainSourceRoot)}: handler for `$throwableName` " +
                        "uses the raw throwable somewhere other than `::class.simpleName` (e.g. " +
                        "passed to Log.*(...) directly) - its message may embed coordinates, " +
                        "deviceId, tokens, or phone numbers (specs/009 §9)"
                }
            }
        }
        assertTrue(
            "CoroutineExceptionHandler(s) that don't log class-name-only found:\n" +
                failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }
}
