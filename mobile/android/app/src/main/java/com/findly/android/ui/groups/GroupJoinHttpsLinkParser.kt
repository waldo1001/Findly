package com.findly.android.ui.groups

/**
 * Pure matcher for the public `https://{JOIN_LINK_HOST}/g#{CODE}` join link (specs/007-public-
 * join-links.md §1/§4, specs/003-android-client.md §12.3). Takes plain `String?` URI components
 * rather than `android.net.Uri` so it's testable in a plain JVM JUnit test (specs/003 §14's
 * no-Robolectric/no-instrumented-test convention) — [com.findly.android.MainActivity] is the
 * one caller that extracts these from a real `Uri` via `.scheme`/`.host`/`.path`/`.fragment`
 * (`android.net.Uri.getFragment()` — **not** `.query`: 007 §1 is explicit the join code travels in
 * the URL **fragment**, never the path or query string, so it's never sent to a server/CDN/proxy
 * and never appears in a log by construction).
 *
 * This is a deliberately different mechanism from the existing `findly://group-join?code=…` deep
 * link, which is matched automatically by Navigation Compose's `navDeepLink { uriPattern = … }`
 * query-argument placeholder syntax (see `FindlyNavHost.kt`) — that placeholder syntax only covers
 * path/query segments, not URL fragments, so the https link is matched by this explicit function
 * instead, called once from `MainActivity` against the launching `Intent`.
 */
object GroupJoinHttpsLinkParser {

    private const val HTTPS_SCHEME = "https"
    private const val JOIN_LINK_PATH = "/g"

    sealed class Result {
        /** Scheme, host, or path didn't match this app's configured join-link surface at all —
         * callers MUST treat this identically to "not a join link" and never navigate to
         * [com.findly.android.ui.nav.Destinations.GroupJoin] because of it (007 §4: "wrong
         * host or path is ignored, never mis-routed"). */
        data object NoMatch : Result()

        /** Scheme+host+path matched. [sanitizedCode] is the fragment run through
         * [GroupJoinCodeSanitizer] — `null` when the fragment was absent, blank, or didn't survive
         * sanitization (007 §4: "a link with a valid host/path but no usable fragment opens the
         * join screen with an empty code field, no error"). Never the raw, unsanitized fragment
         * text — this type cannot represent an untrusted value. */
        data class Matched(val sanitizedCode: String?) : Result()
    }

    /**
     * Scheme/host comparison is case-insensitive (RFC 3986 §3.1 schemes, §3.2.2 host names are
     * both case-insensitive); path comparison is exact and case-sensitive (007 §3's `/g` is a
     * fixed literal, not a case-insensitive identifier — same convention a real web server would
     * apply to its own route table).
     */
    fun parse(scheme: String?, host: String?, path: String?, fragment: String?, joinLinkHost: String): Result {
        val matches = scheme.equals(HTTPS_SCHEME, ignoreCase = true) &&
            host != null &&
            host.equals(joinLinkHost, ignoreCase = true) &&
            path == JOIN_LINK_PATH
        if (!matches) return Result.NoMatch
        return Result.Matched(fragment?.let(GroupJoinCodeSanitizer::sanitize))
    }

    /**
     * [parse] guarded by [isFreshLaunch] (code review fix, 2026-07-22): Android recreates
     * `MainActivity` with a fresh `onCreate` — and so a fresh `FindlyNavHost` composition, and so a
     * fresh `LaunchedEffect(Unit)` — on rotation, dark/light-mode toggle, multi-window resize,
     * font-scale/locale change, and process-death restore, all of which hand `getIntent()` back
     * the **same original launch `Uri`** unchanged. Without this guard, a user who tapped the
     * https link, landed on `GroupJoin`, then navigated elsewhere (e.g. Settings) would get
     * forcibly yanked back to `GroupJoin` by the next rotation, since the recreated Activity would
     * re-parse the same still-matching link and re-trigger the one-time navigation.
     *
     * [com.findly.android.MainActivity] calls this with `isFreshLaunch = (savedInstanceState
     * == null)` — the standard Android idiom for "this `onCreate` is a genuinely new launch, not a
     * config-change/process-death recreation" (the system only supplies a non-null
     * `savedInstanceState` when restoring previously-saved state, which is exactly the set of
     * recreations listed above). On a recreation this unconditionally returns [Result.NoMatch]
     * regardless of how well-formed the (already-handled, now-stale) `Uri` still is, so the
     * one-time navigation fires **at most once per genuinely new launch**, not once per
     * recreation.
     */
    fun parseIfFreshLaunch(
        isFreshLaunch: Boolean,
        scheme: String?,
        host: String?,
        path: String?,
        fragment: String?,
        joinLinkHost: String,
    ): Result = if (isFreshLaunch) parse(scheme, host, path, fragment, joinLinkHost) else Result.NoMatch
}
