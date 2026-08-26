package com.findly.android.ui.invites

/**
 * Pure extraction of a family invite code from arbitrary clipboard text (specs/010-app-shell-and-
 * screen-ux.md §5.2: "Pasting an invite *link* extracts the fragment code via the same 007
 * parsing"), backing the accept-invite screen's explicit-tap "Paste code" affordance. The
 * clipboard may hold a bare code, the `https://{JOIN_LINK_HOST}/f#{CODE}` link, or the
 * `findly://family-join?code={CODE}` deep link — this tries all three, in that order, and returns
 * `null` for anything else (never a crash, never a partial/garbage result).
 *
 * Deliberately plain-string-based (no `android.net.Uri`) so it stays JVM-testable without
 * Robolectric (specs/003-android-client.md §14) — unlike [FamilyInviteHttpsLinkParser]'s callers,
 * which already have a real `Intent`'s pre-parsed `Uri` components, this one has to find those
 * components inside one raw pasted string first. Once it does, the https case delegates to
 * [FamilyInviteHttpsLinkParser.parse] itself (rather than re-deriving the host/path matching
 * rule a second time), so both entry points enforce the exact same host/path/charset gate.
 */
object InviteCodeClipboardExtractor {

    private const val HTTPS_SCHEME_PREFIX = "https://"
    private const val DEEP_LINK_PREFIX = "findly://family-join?code="

    fun extract(clipboardText: String, joinLinkHost: String): String? {
        val trimmed = clipboardText.trim()
        if (trimmed.isEmpty()) return null

        // 1) A bare code, canonical or hyphenated display form.
        FamilyInviteCodeSanitizer.sanitize(trimmed)?.let { return it }

        // 2) The https://{JOIN_LINK_HOST}/f#{CODE} link — decompose into the same
        //    scheme/host/path/fragment shape MainActivity extracts from a real android.net.Uri,
        //    then reuse FamilyInviteHttpsLinkParser's own host/path/charset gate rather than
        //    re-implementing it here.
        if (trimmed.startsWith(HTTPS_SCHEME_PREFIX, ignoreCase = true)) {
            val afterScheme = trimmed.substring(HTTPS_SCHEME_PREFIX.length)
            val hashIndex = afterScheme.indexOf('#')
            val beforeHash = if (hashIndex >= 0) afterScheme.substring(0, hashIndex) else afterScheme
            val fragment = if (hashIndex >= 0) afterScheme.substring(hashIndex + 1) else null
            val slashIndex = beforeHash.indexOf('/')
            val host = if (slashIndex >= 0) beforeHash.substring(0, slashIndex) else beforeHash
            val path = if (slashIndex >= 0) beforeHash.substring(slashIndex) else ""
            val result = FamilyInviteHttpsLinkParser.parse("https", host, path, fragment, joinLinkHost)
            return (result as? FamilyInviteHttpsLinkParser.Result.Matched)?.sanitizedCode
        }

        // 3) The findly://family-join?code={CODE} deep link (never the group-join sibling —
        //    the prefix match is exact, so "findly://group-join?code=…" falls through to null).
        if (trimmed.startsWith(DEEP_LINK_PREFIX, ignoreCase = true)) {
            return FamilyInviteCodeSanitizer.sanitize(trimmed.substring(DEEP_LINK_PREFIX.length))
        }

        return null
    }
}
