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
 * `.kt` file under `src/main` (both the conventional `src/main/java` tree and, were it ever used,
 * `src/main/kotlin` — review round fix, finding 3: the walk starts at `src/main` itself rather
 * than hardcoding the `java` subdirectory), not just the sites named in A42's task brief, so a
 * *new* scope construction added later without a handler fails this test immediately instead of
 * waiting for a fourth review to catch it by hand.
 *
 * Two properties, both required of every real scope construction — `CoroutineScope(...)`,
 * `MainScope()`, or `GlobalScope` (review round fix, finding 4: `MainScope()` **is**
 * `CoroutineScope(SupervisorJob() + Dispatchers.Main)` with no handler and can never be given one —
 * it takes no arguments — so it is banned outright, same as `GlobalScope`, which is a bare
 * singleton object with no handler and no component lifecycle of its own) (comments are stripped
 * first so a doc comment merely *mentioning* one of these names — several files here do,
 * describing exactly this bug — can never itself trip the assertion):
 *
 * 1. The site carries a [kotlinx.coroutines.CoroutineExceptionHandler] — inline, or by reference to
 *    a same-file named `val` that is itself assigned `CoroutineExceptionHandler(...)` (review round
 *    fix, finding 2: resolved by an actual same-file `val` lookup, not by guessing from the
 *    identifier's spelling) — never a bare `SupervisorJob() + Dispatchers.X`.
 * 2. Where that handler logs, it logs the throwable's class name only (specs/009-device-runtime.md
 *    §9: "Never log coordinates, `deviceId`, phone numbers, or tokens... Counts and error codes
 *    only") — never the throwable/exception object itself, whose `message` can embed exactly that
 *    forbidden payload (a location or Retrofit exception's message routinely does). A
 *    `CoroutineExceptionHandler` not written as `{ params -> ... }` (a function reference, an
 *    `object : CoroutineExceptionHandler`) cannot be read this way at all — review round fix,
 *    finding 1: rather than silently skipping it, every such declaration is now counted and any
 *    that isn't matched by the body regex fails the test outright, so the checkable shape is
 *    mandatory instead of merely preferred.
 *
 * **`rememberCoroutineScope()` is out of scope for both properties above — structurally, not by
 * lifecycle.** (Review round fix, finding 5: the previous wording here justified the exclusion by
 * composition lifecycle, which is not the relevant property — a `rememberCoroutineScope()` scope
 * carries no handler and an uncaught throw from a `launch` on it kills the process exactly like any
 * other unguarded scope; two call sites were exactly that live bug, fixed at the call site with a
 * silent `try`/`catch`, see `AcceptInviteScreen.kt`/`CreateInviteScreen.kt`.) The real reason this
 * test can't require a handler on it is that Compose's API gives no way to attach one — there is no
 * `rememberCoroutineScope(handler)` overload — so the convention is enforced differently for these
 * sites: audit every `rememberCoroutineScope()` launch body by hand and either wrap it in a silent
 * `try`/`catch` (if it can throw something other than cancellation) or leave it bare only when the
 * body provably can throw nothing but `CancellationException` (never delivered to any handler, so
 * structurally safe either way — true for `FindlyBottomSheet.kt`'s `snapTo` and
 * `FindlyNavHost.kt`'s `drawerState.close()`, both `Animatable`/drawer APIs that throw only that).
 * `rememberCoroutineScope()` sites are excluded from the two mechanical properties above by the
 * same word-boundary the construction-site regex uses (it requires a non-identifier character, or
 * start of file, immediately before `CoroutineScope(`, which the `remember` prefix fails).
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

    /** Review round fix, finding 3: was `File(moduleRoot, "src/main/java")`, which silently never
     * looked at `src/main/kotlin` — a production `.kt` file placed there (Kotlin/AGP happily
     * compiles both source sets) was invisible to every check below. Walking `src/main` itself
     * covers both, and any future source set under `src/main`, with no hardcoded subdirectory. */
    private val mainSourceRoot: File
        get() = File(moduleRoot, "src/main")

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

    /** Identifiers referenced inside a construction site's argument list, minus the small set of
     * names every site legitimately combines with `+` that are never themselves a handler. Used to
     * resolve a site that carries its handler *by reference* (review round fix, finding 2). */
    private val nonHandlerScopeIdentifiers = setOf(
        "SupervisorJob", "Dispatchers", "Default", "IO", "Main", "Unconfined", "Job", "CoroutineScope",
    )

    private fun bareIdentifiers(site: String): List<String> =
        Regex("""[A-Za-z_][A-Za-z0-9_]*""").findAll(site).map { it.value }.distinct()
            .filterNot { it in nonHandlerScopeIdentifiers }
            .toList()

    private val handlerTypeReference = Regex("""(?<![A-Za-z0-9_])CoroutineExceptionHandler(?![A-Za-z0-9_])""")

    private fun siteHasInlineHandler(site: String): Boolean = handlerTypeReference.containsMatchIn(site)

    /** Review round fix, finding 2: was `site.contains("exceptionhandler", ignoreCase = true)`,
     * which false-negatived a compliant handler val merely not named to contain that substring
     * (e.g. `ceh`) and false-positived any identifier that happened to contain it without being a
     * handler at all. A bare identifier referenced in a site now only counts if it resolves, in
     * the same file, to a `val <name> ... = CoroutineExceptionHandler` declaration. */
    private fun siteReferencesDeclaredHandler(site: String, source: String): String? =
        bareIdentifiers(site).firstOrNull { name ->
            Regex("""\bval\s+${Regex.escape(name)}\b[^=\n]*=\s*CoroutineExceptionHandler\b""").containsMatchIn(source)
        }

    private val mainScopeSite = Regex("""(?<![A-Za-z0-9_])MainScope\s*\(\s*\)""")
    private val globalScopeReference = Regex("""(?<![A-Za-z0-9_])GlobalScope(?![A-Za-z0-9_])""")

    @Test
    fun `every CoroutineScope construction site carries a CoroutineExceptionHandler`() {
        val failures = mutableListOf<String>()
        for (file in kotlinSourceFiles()) {
            val source = stripComments(file.readText())
            for (site in constructionSites(source)) {
                if (siteHasInlineHandler(site) || siteReferencesDeclaredHandler(site, source) != null) continue
                val candidates = bareIdentifiers(site).filter { Regex("""^[A-Za-z_]\w*$""").matches(it) }
                val resolutionHint = if (candidates.isNotEmpty()) {
                    " — references ${candidates.joinToString()} but no `val <name> ... = " +
                        "CoroutineExceptionHandler` declaration for any of them was found in this " +
                        "file; a handler carried by reference MUST resolve to a same-file " +
                        "`val ... = CoroutineExceptionHandler(...)` declaration"
                } else {
                    ""
                }
                failures += "${file.relativeTo(mainSourceRoot)}: $site$resolutionHint"
            }
            // Review round fix, finding 4: MainScope() carries no CoroutineExceptionHandler and can
            // never be given one (it takes no arguments) — every use is a violation by construction.
            if (mainScopeSite.containsMatchIn(source)) {
                failures += "${file.relativeTo(mainSourceRoot)}: MainScope() carries no " +
                    "CoroutineExceptionHandler and can never be given one (it takes no arguments) " +
                    "— use CoroutineScope(SupervisorJob() + Dispatchers.Main + " +
                    "CoroutineExceptionHandler { _, throwable -> ... }) instead"
            }
            // Review round fix, finding 4: GlobalScope is banned outright (specs/003 §3.1) — it
            // carries no CoroutineExceptionHandler, cannot be given one, and is not scoped to any
            // component's lifecycle.
            if (globalScopeReference.containsMatchIn(source)) {
                failures += "${file.relativeTo(mainSourceRoot)}: GlobalScope is banned outright " +
                    "(specs/003-android-client.md §3.1) — it carries no CoroutineExceptionHandler " +
                    "and is not scoped to any component's lifecycle; construct a proper " +
                    "CoroutineScope(...) with a handler instead"
            }
        }
        assertTrue(
            "Found CoroutineScope( construction site(s) with no CoroutineExceptionHandler (or a " +
                "MainScope()/GlobalScope use, which can never carry one). A SupervisorJob does NOT " +
                "swallow exceptions - it only isolates sibling coroutines from each other's " +
                "failures - so any uncaught throw from any launch{} on one of these scopes reaches " +
                "the default handler and kills the whole process (A39/A40/A41 found this three " +
                "times running). Add a CoroutineExceptionHandler that logs the exception's class " +
                "name only:\n" + failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }

    /** The real handlers in this module use the `{ _, throwable -> ... }` shape, optionally with
     * explicit parameter types (review round fix, finding 1: was `\w+` only either side of the
     * comma, which never matched `{ _: CoroutineContext, throwable: Throwable -> ... }` — a
     * perfectly legal, equally common way to write this lambda). Captures the throwable parameter's
     * name so the check works even if a future handler renames it. */
    private val handlerRegex = Regex(
        """CoroutineExceptionHandler\s*\{\s*\w+(?:\s*:\s*[\w.<>?]+)?\s*,\s*(\w+)(?:\s*:\s*[\w.<>?]+)?\s*->""",
    )

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

    /** Every occurrence of the bare `CoroutineExceptionHandler` type name in this file that isn't
     * the import line — i.e. every place the type is actually constructed or referenced as a type,
     * whether or not it's written in the one shape [handlerRegex] can parse (review round fix,
     * finding 1). Used to fail closed: a `CoroutineExceptionHandler(::someFunction)` or
     * `object : CoroutineExceptionHandler { ... }` must still be *counted* even though this test
     * can't read inside it, so it can never silently skip the logging check instead of flagging
     * that it can't run it. */
    private fun handlerDeclarationOccurrences(source: String): List<String> {
        val withoutImports = source.lineSequence()
            .filterNot { it.trimStart().startsWith("import ") }
            .joinToString("\n")
        return handlerTypeReference.findAll(withoutImports).map { it.value }.toList()
    }

    @Test
    fun `every CoroutineExceptionHandler logs the throwable's class name only, never the throwable itself`() {
        val failures = mutableListOf<String>()
        for (file in kotlinSourceFiles()) {
            val source = stripComments(file.readText())
            val declarationCount = handlerDeclarationOccurrences(source).size
            val bodies = handlerBodies(source)
            if (bodies.size < declarationCount) {
                failures += "${file.relativeTo(mainSourceRoot)}: found $declarationCount " +
                    "CoroutineExceptionHandler declaration(s) but could only verify the logging " +
                    "body of ${bodies.size} of them — write it as `CoroutineExceptionHandler { " +
                    "_, throwable -> ... }` (explicit parameter types are fine) so this test can " +
                    "check what it logs; a function reference (`CoroutineExceptionHandler(::fn)`) " +
                    "or an `object : CoroutineExceptionHandler { ... }` cannot be verified this way " +
                    "and must not be used"
                continue
            }
            for ((throwableName, body) in bodies) {
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
            "CoroutineExceptionHandler(s) that don't log class-name-only found (or couldn't be " +
                "verified at all):\n" + failures.joinToString("\n"),
            failures.isEmpty(),
        )
    }
}
