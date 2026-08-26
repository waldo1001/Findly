package com.findly.android.ui.groups

import com.findly.android.joincode.JoinCodeAlphabet

/**
 * Pure group-join-code normalizer/validator (001-api-contract.md §1.4), applied to **every**
 * incoming code before it is used — both the manual entry field on [GroupJoinScreen] and, more
 * importantly, the `findly://group-join?code=…` deep link's `code` query parameter, which is
 * **untrusted external input** (any app on the device, or a malicious link, can launch it with an
 * arbitrary string). Mirrors [com.findly.android.auth.PhoneNumberNormalizer]'s shape: a plain
 * `object` with a single `normalize`-style function returning `null` on anything that doesn't fit
 * — callers MUST NOT make a network call (or otherwise trust the value) when this returns `null`.
 *
 * Wire format (001 §1.4): 8 characters of Crockford base32 (digits `0-9` plus `A-Z` **minus**
 * `I`/`L`/`O`/`U`, to avoid visual ambiguity). Canonical form is uppercase, no hyphen; clients MAY
 * display/accept the `XXXX-XXXX` grouping and the server ignores case/hyphens.
 *
 * **A36 (specs/010-app-shell-and-screen-ux.md §5) refactor:** the actual strip/uppercase/validate
 * logic now lives once, in [JoinCodeAlphabet], shared with family invite codes'
 * [com.findly.android.ui.invites.FamilyInviteCodeSanitizer] twin — both wire formats are the
 * identical 001 §1.4 rule, so this object is now a thin, behavior-preserving alias rather than a
 * second copy of the regex/strip/uppercase logic (verified unchanged against
 * `GroupJoinCodeSanitizerTest`, written before this class existed).
 */
object GroupJoinCodeSanitizer {

    /**
     * Strips surrounding whitespace and the display hyphen, upper-cases, then validates against
     * the closed Crockford-base32 8-char alphabet. Returns `null` for anything that doesn't
     * normalize into a well-formed code — including embedded whitespace, wrong length, excluded
     * letters, or arbitrary untrusted text (deep-link injection attempts, HTML, SQL-looking
     * strings, path traversal, …): none of those can ever produce a non-null result here, since
     * the output alphabet is a strict whitelist, not a blacklist of "bad" characters.
     */
    fun sanitize(input: String): String? = JoinCodeAlphabet.sanitize(input)
}
