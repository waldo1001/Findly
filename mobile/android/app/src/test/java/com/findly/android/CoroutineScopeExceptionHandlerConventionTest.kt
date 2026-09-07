package com.findly.android

import java.io.File
import org.junit.Assert.assertEquals
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

    /** Third review round fix, finding 1: replaces the interior (and delimiters) of every string
     * literal — a regular `"..."` (respecting `\"` escapes so an escaped quote never ends the
     * literal early) or a triple-quoted `"""..."""` (no escape processing, per Kotlin) — with
     * spaces, preserving length and newlines so every index into the result still lines up with
     * [source]. Applied once, up front, so every brace/paren depth-counting loop and every regex
     * match below it — [constructionSites]' and [handlerBodies]' matching parenthesis/brace scans,
     * [handlerTypeReference], [handlerDeclarationOccurrences], [mainScopeSite],
     * [globalScopeReference] — is automatically blind to text an author merely wrote *inside* a
     * string (a `}` in an ordinary log message, `CoroutineExceptionHandler` named in an error
     * string) without any of them needing their own string-literal awareness. The reviewer's exact
     * defeat snippet was a `}` inside `"}"` inside a handler body's own string argument, which
     * dropped [handlerBodies]' naive `{`/`}` depth count to zero early and hid everything after it
     * — including the real throwable leak the test exists to catch.
     *
     * **String-template interpolation (`${'$'}{expr}`, `${'$'}identifier`) is left un-masked.** A
     * first version of this fix masked template bodies too, which broke the compliant
     * `Log.d(TAG, "unhandled failure (${'$'}{throwable::class.simpleName})")` shape several real
     * handlers in this module use (`AppContainer.kt`, `LocateForegroundService.kt`,
     * `LocationForegroundService.kt`, `BootCompletedReceiver.kt`,
     * `GeofenceTransitionReceiver.kt`) — masking the whole string blanked out the very
     * `throwable::class.simpleName` expression the logging check looks for, turning entirely
     * compliant code into five false fails. A template's expression is real, executable Kotlin
     * (which can itself contain further string literals, so `${'$'}{...}` recurses back through
     * the same masking) — only the literal text *around* a template is ever masked. */
    private fun maskStringLiterals(source: String): String {
        val out = CharArray(source.length) { ' ' }

        // Kotlin local functions can't forward-reference each other, but these two are mutually
        // recursive by construction (real code can contain a string, whose `${...}` template can
        // contain more real code, which can contain another string, ...), so they're declared as
        // lateinit lambdas assigned in dependency order instead of `fun`.
        lateinit var maskCode: (from: Int, inTemplate: Boolean) -> Int
        lateinit var maskString: (from: Int, triple: Boolean) -> Int

        maskCode = { from, inTemplate ->
            var i = from
            var depth = 0
            while (i < source.length) {
                when {
                    source.startsWith("\"\"\"", i) -> i = maskString(i + 3, true)
                    source[i] == '"' -> i = maskString(i + 1, false)
                    inTemplate && source[i] == '{' -> {
                        depth++
                        out[i] = source[i]
                        i++
                    }
                    inTemplate && source[i] == '}' && depth == 0 -> {
                        // The template's own closing delimiter, matching the `${` that was
                        // itself masked (not copied) below — mask this one too, symmetrically,
                        // so a downstream naive brace counter (handlerBodies, constructionSites)
                        // never sees an unmatched `}` where the `{` half was masked away.
                        i++
                        depth = -1 // sentinel: stop the loop below via the break check
                    }
                    inTemplate && source[i] == '}' -> {
                        depth--
                        out[i] = source[i]
                        i++
                    }
                    else -> {
                        out[i] = source[i]
                        i++
                    }
                }
                if (inTemplate && depth == -1) break
            }
            i
        }

        maskString = { from, triple ->
            var i = from
            var closed = false
            while (i < source.length && !closed) {
                when {
                    !triple && source[i] == '\\' -> i += if (i + 1 < source.length) 2 else 1
                    !triple && source[i] == '"' -> {
                        i++
                        closed = true
                    }
                    triple && source.startsWith("\"\"\"", i) -> {
                        i += 3
                        closed = true
                    }
                    source[i] == '$' && i + 1 < source.length && source[i + 1] == '{' ->
                        i = maskCode(i + 2, true)
                    source[i] == '$' && i + 1 < source.length &&
                        (source[i + 1].isLetter() || source[i + 1] == '_') -> {
                        var j = i + 1
                        while (j < source.length && (source[j].isLetterOrDigit() || source[j] == '_')) {
                            out[j] = source[j]
                            j++
                        }
                        i = j
                    }
                    else -> {
                        if (source[i] == '\n') out[i] = '\n'
                        i++
                    }
                }
            }
            i
        }

        maskCode(0, false)
        return String(out)
    }

    /** The single preprocessing pipeline every scan below runs on: strip comments, then mask out
     * string-literal interiors. Every `@Test` and every direct scanner-unit-test in this file goes
     * through this one function so the two stages can never drift out of sync with each other. */
    private fun preprocessSource(rawText: String): String = maskStringLiterals(stripComments(rawText))

    /** Every real `CoroutineScope(` construction — not `rememberCoroutineScope()`, excluded by the
     * negative lookbehind requiring a non-letter (or start of file) immediately before the match —
     * as the full text between (and including) its balanced parentheses. Operates on already
     * comment-stripped, string-masked source ([preprocessSource]), so a `)` an author happened to
     * write inside a string literal can never be mistaken for the real closing paren. */
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
    /** Third review round fix, finding 2: the RHS match used to require `CoroutineExceptionHandler`
     * to appear immediately after `=` (only whitespace allowed between), so the very ordinary
     * refactor of hoisting the context into a named `val` —
     * `val ctx = SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { ... }` then
     * `CoroutineScope(ctx)` — false-failed because the RHS *starts* with `SupervisorJob()`, not the
     * handler. The RHS is now searched for `CoroutineExceptionHandler` anywhere after the `=`,
     * still bounded to one line (`[^;\n]*`, no `;`/newline crossed) so it can never accidentally
     * bleed into a different statement or a different `val`'s declaration. A `+`-combined RHS whose
     * pieces are split across multiple lines is not resolved by this — see specs/003 §3.1's known
     * blind spots. */
    private fun siteReferencesDeclaredHandler(site: String, source: String): String? =
        bareIdentifiers(site).firstOrNull { name ->
            Regex(
                """\bval\s+${Regex.escape(name)}\b[^=\n]*=[^;\n]*(?<![A-Za-z0-9_])CoroutineExceptionHandler\b""",
            ).containsMatchIn(source)
        }

    private val mainScopeSite = Regex("""(?<![A-Za-z0-9_])MainScope\s*\(\s*\)""")
    private val globalScopeReference = Regex("""(?<![A-Za-z0-9_])GlobalScope(?![A-Za-z0-9_])""")

    @Test
    fun `every CoroutineScope construction site carries a CoroutineExceptionHandler`() {
        val failures = mutableListOf<String>()
        for (file in kotlinSourceFiles()) {
            val source = preprocessSource(file.readText())
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
        return handlerTypeReference.findAll(withoutImports)
            .filterNot { match -> isReturnTypeAnnotationPosition(withoutImports, match.range.first) }
            .map { it.value }
            .toList()
    }

    /** Third review round fix, finding 2: a bare mention in a function's return-type position
     * (`private fun makeHandler(): CoroutineExceptionHandler`) is a mere type annotation, not a
     * construction — counting it here double-counted an ordinary factory function against the
     * single real construction on its body/RHS and false-failed entirely correct code. Only this
     * specific, unambiguous shape is excluded (a `)` then `:` immediately before the name);
     * `object : CoroutineExceptionHandler { ... }` is preceded by the `object` keyword, not `)`, so
     * it is still counted and still fails closed, as intended. A constructor-parameter or property
     * type annotation (`class Foo(private val handler: CoroutineExceptionHandler)`) is a narrower,
     * still-open instance of the same class of false positive — see specs/003 §3.1's known blind
     * spots. */
    private fun isReturnTypeAnnotationPosition(text: String, matchStart: Int): Boolean =
        Regex("""\)\s*:\s*$""").containsMatchIn(text.substring(0, matchStart))

    @Test
    fun `every CoroutineExceptionHandler logs the throwable's class name only, never the throwable itself`() {
        val failures = mutableListOf<String>()
        for (file in kotlinSourceFiles()) {
            val source = preprocessSource(file.readText())
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

    // --- Third review round, finding 1: adversarial fixtures for the string-literal defeat. ---

    /** Reviewer's exact defeat snippet (quoted verbatim in the A42 task brief): a `}` inside the
     * ordinary string `"}"` used to drop [handlerBodies]' naive brace-depth count to zero early, so
     * everything after it — including the real §9 leak on the
     * `Log.w(TAG, throwable.message ?: "", throwable)` line — was never examined. Exercises the
     * real scanning function directly against this exact text, independent of any file under
     * `src/main`, so this regression can never again depend on a fixture file surviving in the
     * production tree. */
    @Test
    fun `handlerBodies does not stop scanning at a brace inside an ordinary string literal`() {
        val snippet = """
            fun start() {
                CoroutineScope(SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                    Log.d(TAG, "failure: ${'$'}{throwable::class.simpleName}")
                    val bogus = "}"
                    Log.w(TAG, throwable.message ?: "", throwable)
                })
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val bodies = handlerBodies(source)
        assertEquals(1, bodies.size)
        val (throwableName, body) = bodies.single()
        assertEquals("throwable", throwableName)
        assertTrue(
            "handlerBodies truncated the handler body at the brace inside the string literal " +
                "\"}\" instead of the real closing brace of the CoroutineExceptionHandler lambda " +
                "— the leaking Log.w(...) line was never captured:\n$body",
            body.contains("Log.w(TAG, throwable.message"),
        )
    }

    /** Same defect class as above, in [constructionSites]' paren-depth count (task brief: "the
     * construction-site scan around line 99"): a `)` inside an ordinary string literal must not be
     * mistaken for the real closing paren of `CoroutineScope(...)`. */
    @Test
    fun `constructionSites does not stop scanning at a parenthesis inside an ordinary string literal`() {
        val snippet = """
            fun start() {
                CoroutineScope(
                    SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                        val bogus = ")"
                        Log.d(TAG, throwable::class.simpleName ?: "unknown")
                    }
                )
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val sites = constructionSites(source)
        assertEquals(1, sites.size)
        val site = sites.single()
        assertTrue(
            "constructionSites truncated the site at the parenthesis inside the string literal " +
                "\")\" instead of the real closing paren of CoroutineScope(...) — everything after " +
                "it was never captured as part of the site:\n$site",
            site.contains("Log.d(TAG, throwable::class.simpleName"),
        )
    }

    /** Regression guard for [maskStringLiterals] itself, added after a first version of the finding
     * 1 fix masked template bodies wholesale and false-failed five real, compliant handlers in this
     * module — `AppContainer.kt`, `LocateForegroundService.kt`, `LocationForegroundService.kt`,
     * `BootCompletedReceiver.kt`, `GeofenceTransitionReceiver.kt` — all of which log via
     * `"...(${'$'}{throwable::class.simpleName})"` string-template interpolation rather than a
     * plain trailing `Log.d(TAG, throwable::class.simpleName)` argument. The `${'$'}{...}`
     * expression is real code and must remain visible to the logging check. */
    @Test
    fun `a compliant handler logging via string-template interpolation is still recognized`() {
        val snippet = """
            private val handler = CoroutineExceptionHandler { _, throwable ->
                Log.d(TAG, "unhandled failure (${'$'}{throwable::class.simpleName})")
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val bodies = handlerBodies(source)
        assertEquals(1, bodies.size)
        val (_, body) = bodies.single()
        assertTrue(
            "masking the string literal also masked away the real " +
                "\${throwable::class.simpleName} template expression inside it, which is how " +
                "several real handlers in this codebase log compliantly:\n$body",
            Regex("""throwable\s*::\s*class\s*\.\s*simpleName""").containsMatchIn(body),
        )
    }

    // --- Third review round, finding 2: adversarial fixtures for the fail-closed false-fails. ---

    /** A factory function's return-type annotation (`private fun makeHandler(): " +
     * "CoroutineExceptionHandler`) is a mere type mention, not a construction — it must not be
     * double-counted against the one real construction on the function's body/RHS, or entirely
     * correct code false-fails the fail-closed count check. */
    @Test
    fun `a factory function's return-type annotation does not double-count as a second handler declaration`() {
        val snippet = """
            private fun makeHandler(): CoroutineExceptionHandler = CoroutineExceptionHandler { _, throwable ->
                Log.d(TAG, throwable::class.simpleName ?: "unknown")
            }
        """.trimIndent()
        val source = stripComments(snippet)
        val declarationCount = handlerDeclarationOccurrences(source).size
        val bodyCount = handlerBodies(source).size
        assertEquals(
            "the return-type mention of CoroutineExceptionHandler in `makeHandler(): " +
                "CoroutineExceptionHandler` was counted as a second declaration alongside the real " +
                "construction on the RHS, so the fail-closed count check flags this entirely " +
                "correct code as unverifiable (declarations=$declarationCount, bodies=$bodyCount)",
            bodyCount,
            declarationCount,
        )
    }

    /** Guard against over-correcting the above: an `object : CoroutineExceptionHandler { ... }`
     * also has a `:` before the type name, but it is preceded by the `object` keyword, not `)` —
     * it must still be counted and still fail closed (it cannot be verified). */
    @Test
    fun `an unparseable object-expression handler is still counted and fails closed`() {
        val snippet = """
            private val handler = object : CoroutineExceptionHandler {
                override fun handleException(context: CoroutineContext, exception: Throwable) {
                    Log.d(TAG, exception::class.simpleName ?: "unknown")
                }
            }
        """.trimIndent()
        val source = stripComments(snippet)
        assertEquals(1, handlerDeclarationOccurrences(source).size)
        assertEquals(0, handlerBodies(source).size)
    }

    /** A log/error message that merely names `CoroutineExceptionHandler` in prose must not count
     * as a declaration — string-literal content must never be mistaken for a real reference to the
     * type. */
    @Test
    fun `a log message merely naming CoroutineExceptionHandler in prose does not count as a declaration`() {
        val snippet = """
            private val handler = CoroutineExceptionHandler { _, throwable ->
                Log.e(TAG, "CoroutineExceptionHandler misconfiguration: " + (throwable::class.simpleName ?: "unknown"))
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        assertEquals(1, handlerDeclarationOccurrences(source).size)
        assertEquals(1, handlerBodies(source).size)
    }

    /** The ordinary refactor of hoisting a handler into a named, `+`-combined context `val` —
     * `val ctx = SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { ... }` then
     * `CoroutineScope(ctx)` — must resolve `ctx` as carrying a handler; the old regex only matched
     * a RHS that *starts* with `CoroutineExceptionHandler`. */
    @Test
    fun `a handler hoisted into a plus-combined context val is resolved by reference`() {
        val snippet = """
            fun start() {
                val ctx = SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                    Log.d(TAG, throwable::class.simpleName ?: "unknown")
                }
                val scope = CoroutineScope(ctx)
            }
        """.trimIndent()
        val source = stripComments(snippet)
        val sites = constructionSites(source)
        assertEquals(1, sites.size)
        val site = sites.single()
        assertTrue(
            "CoroutineScope(ctx) was not recognized as carrying a handler even though `ctx` is a " +
                "same-file val whose +-combined right-hand side includes CoroutineExceptionHandler",
            siteHasInlineHandler(site) || siteReferencesDeclaredHandler(site, source) != null,
        )
    }

    // --- A42 defect fix: stripComments (naive `//`/`/* */` regex) ran BEFORE string masking, so a
    // `//` an author wrote *inside* a string literal was read as a real comment - deleting the rest
    // of that line, including the string's own closing quote. String masking then treated the
    // string as unterminated and searched forward for the next `"` in the file (or ran to EOF if
    // none existed), hiding every real CoroutineScope(...) construction in between. This is
    // fail-open - the opposite direction from every blind spot specs/003 §3.1 previously documented.
    // Three shipped files already have this shape: GroupJoinLinkBuilder.kt (no later `"` at all, so
    // masking ran to EOF), Destinations.kt, and DevAuthProvider.kt.

    /** The minimal reproduction: a `//` inside an ordinary string, with a second, unrelated string
     * later in the file. Under the old two-pass pipeline, the `//` truncated its line (eating the
     * string's own closing quote), and string masking then treated the *later* string's opening `"`
     * as the "closing" of the truncated one - masking everything in between, including the real
     * CoroutineScope(...) construction site that sits between the two strings. */
    @Test
    fun `a slash-slash inside an ordinary string literal does not truncate the line or hide later code`() {
        val snippet = """
            fun start() {
                val url = "https://example.com/x"
                CoroutineScope(SupervisorJob() + Dispatchers.Default)
                val other = "unrelated"
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val sites = constructionSites(source)
        assertEquals(
            "the // inside \"https://example.com/x\" was treated as a comment, truncating the line " +
                "and eating the string's closing quote, which then let the next \" in the file " +
                "(\"unrelated\"'s opening quote) masquerade as its closing quote, hiding the real " +
                "CoroutineScope(...) construction site in between",
            1,
            sites.size,
        )
    }

    /** The exact `GroupJoinLinkBuilder.kt` shape: a `//`-containing string with NO later `"`
     * anywhere else in the file. Under the old pipeline this is worse than the case above - with no
     * later quote to (incorrectly) close the string, masking ran all the way to end of file, so the
     * unguarded CoroutineScope(...) after it was never reported at all. */
    @Test
    fun `a slash-slash inside a string with no later quote in the file still leaves later code scannable (GroupJoinLinkBuilder shape)`() {
        val snippet = """
            object Probe {
                private const val url = "https://example.com/no-later-quote"
                val probeScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            }
        """.trimIndent()
        // Sanity check on the fixture itself: exactly one string (two quote characters, the url's
        // own open/close) in the whole file, and no other `"` anywhere later - this is what makes
        // the old pipeline's "search forward for the next quote" run all the way to EOF.
        assertEquals(2, snippet.count { it == '"' })
        val source = preprocessSource(snippet)
        assertEquals(
            "the unguarded CoroutineScope(...) after the // string was hidden because masking ran " +
                "to end of file with no later \" to (incorrectly) stop at",
            1,
            constructionSites(source).size,
        )
    }

    /** A `"` written inside a `//` line comment must never be read as opening a string. */
    @Test
    fun `a quote inside a slash-slash comment does not start a string`() {
        val snippet = """
            fun start() {
                // a comment mentioning a "quote" and even /* nested-looking */ text
                CoroutineScope(SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                    Log.d(TAG, throwable::class.simpleName ?: "unknown")
                })
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val sites = constructionSites(source)
        assertEquals(1, sites.size)
        assertTrue(
            "the \" inside the // comment was misread as opening a string, hiding the real handler",
            siteHasInlineHandler(sites.single()),
        )
    }

    /** A `"` written inside a `/* */` block comment must never be read as opening a string. */
    @Test
    fun `a quote inside a block comment does not start a string`() {
        val snippet = """
            fun start() {
                /* a block comment mentioning a "quote" and a // slash-slash too */
                CoroutineScope(SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                    Log.d(TAG, throwable::class.simpleName ?: "unknown")
                })
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val sites = constructionSites(source)
        assertEquals(1, sites.size)
        assertTrue(
            "the \" inside the block comment was misread as opening a string, hiding the real handler",
            siteHasInlineHandler(sites.single()),
        )
    }

    /** A Kotlin CHAR literal containing a double quote (`'"'`) must not be read as opening a
     * string - currently unhandled by both the old and new scanner until this fix, per the task
     * brief: there is no production example today, so this is unit-only coverage. Without char-literal
     * awareness, the `"` inside `'"'` would be read as a real string-open, and the scan would then
     * search forward for the next `"` - here, `"unknown"`'s opening quote - masking everything in
     * between, including the real handler. */
    @Test
    fun `a char literal containing a double quote does not start a string`() {
        val snippet = """
            fun start() {
                val quoteChar = '"'
                CoroutineScope(SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                    Log.d(TAG, throwable::class.simpleName ?: "unknown")
                })
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val sites = constructionSites(source)
        assertEquals(1, sites.size)
        assertTrue(
            "the \" inside the '\"' char literal was misread as opening a string, hiding the real " +
                "handler",
            siteHasInlineHandler(sites.single()),
        )
    }

    /** A raw `"""..."""` string containing both `//` and a lone `"` must be masked as one string,
     * not misread as a comment or an early-closing string. Built via `${"\"\"\""}` template
     * expressions in the outer fixture string (rather than literal `"""` sequences) purely so the
     * Kotlin source of *this test file* doesn't itself get confused about where its own triple-quote
     * fixture string ends. */
    @Test
    fun `a raw triple-quoted string containing slash-slash and a quote is not treated as code`() {
        val snippet = """
            fun start() {
                val raw = ${"\"\"\""}has a // slash-slash and a " quote inside${"\"\"\""}
                CoroutineScope(SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, throwable ->
                    Log.d(TAG, throwable::class.simpleName ?: "unknown")
                })
            }
        """.trimIndent()
        val source = preprocessSource(snippet)
        val sites = constructionSites(source)
        assertEquals(1, sites.size)
        assertTrue(
            "content inside the raw triple-quoted string was misread as a comment or as ending the " +
                "string early, hiding the real handler",
            siteHasInlineHandler(sites.single()),
        )
    }
}
