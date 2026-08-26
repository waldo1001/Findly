package com.findly.android.ui.invites

/**
 * Pure matcher for the public `https://{JOIN_LINK_HOST}/f#{CODE}` family-invite link
 * (specs/007-public-join-links.md §1/§4 as amended 2026-08-26, specs/010-app-shell-and-screen-
 * ux.md §5.2) — the family twin of
 * [com.findly.android.ui.groups.GroupJoinHttpsLinkParser], distinguished only by the `/f` path
 * (never `/g` — 007 §1: "Consumers MUST NOT treat one as the other"). Takes plain `String?` URI
 * components rather than `android.net.Uri` so it's testable in a plain JVM JUnit test (specs/003
 * §14) — [com.findly.android.MainActivity] is the one caller that extracts these from a real
 * `Uri` via `.scheme`/`.host`/`.path`/`.fragment` (never `.query` — the code lives in the URL
 * **fragment**, never sent to a server/CDN/proxy, 007 §1's load-bearing privacy property, doubly
 * so here since family invite codes are single-use, 007 §1's amendment).
 */
object FamilyInviteHttpsLinkParser {

    private const val HTTPS_SCHEME = "https"
    private const val INVITE_LINK_PATH = "/f"

    sealed class Result {
        /** Scheme, host, or path didn't match this app's configured family-invite link surface
         * at all — callers MUST treat this identically to "not a family-invite link" and never
         * navigate to the accept-invite screen because of it (007 §4: "wrong host or path is
         * ignored, never mis-routed"). */
        data object NoMatch : Result()

        /** Scheme+host+path matched. [sanitizedCode] is the fragment run through
         * [FamilyInviteCodeSanitizer] — `null` when the fragment was absent, blank, or didn't
         * survive sanitization (007 §4: "a link with a valid host/path but no usable fragment
         * opens the join screen with an empty code field, no error"). Never the raw, unsanitized
         * fragment text. */
        data class Matched(val sanitizedCode: String?) : Result()
    }

    /**
     * Scheme/host comparison is case-insensitive (RFC 3986 §3.1/§3.2.2); path comparison is
     * exact and case-sensitive — `/f` is a fixed literal, and deliberately never matches `/g`
     * (the group-invite path) or vice versa (007 §1's amendment: "Consumers MUST NOT treat one
     * as the other").
     */
    fun parse(scheme: String?, host: String?, path: String?, fragment: String?, joinLinkHost: String): Result {
        val matches = scheme.equals(HTTPS_SCHEME, ignoreCase = true) &&
            host != null &&
            host.equals(joinLinkHost, ignoreCase = true) &&
            path == INVITE_LINK_PATH
        if (!matches) return Result.NoMatch
        return Result.Matched(fragment?.let(FamilyInviteCodeSanitizer::sanitize))
    }

    /**
     * [parse] guarded by [isFreshLaunch] — mirrors
     * [com.findly.android.ui.groups.GroupJoinHttpsLinkParser.parseIfFreshLaunch]'s rotation/
     * recreation guard exactly (see its doc for the full reasoning): Android recreates
     * `MainActivity` with a fresh `onCreate` on rotation, dark/light toggle, multi-window resize,
     * font-scale/locale change, and process-death restore, all of which hand `getIntent()` back
     * the same original launch `Uri`. Without this guard, a user who tapped the link, navigated
     * elsewhere, then rotated, would get yanked back to the accept-invite screen.
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
