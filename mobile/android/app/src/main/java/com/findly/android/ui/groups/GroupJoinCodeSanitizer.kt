package com.findly.android.ui.groups

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
 * display/accept the `XXXX-XXXX` grouping and the server ignores case/hyphens — so this sanitizer
 * strips whitespace and hyphens and upper-cases before validating, exactly mirroring the server's
 * own acceptance rule, then rejects anything that still isn't exactly 8 valid characters.
 */
object GroupJoinCodeSanitizer {

    /** Crockford base32 alphabet, excluding I/L/O/U (001 §1.4). Spelled out explicitly (not as
     * regex character-class ranges) so the excluded letters are unambiguous at a glance. */
    private val VALID_CODE = Regex("^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{8}$")

    /**
     * Strips surrounding whitespace and the display hyphen, upper-cases, then validates against
     * the closed Crockford-base32 8-char alphabet. Returns `null` for anything that doesn't
     * normalize into a well-formed code — including embedded whitespace, wrong length, excluded
     * letters, or arbitrary untrusted text (deep-link injection attempts, HTML, SQL-looking
     * strings, path traversal, …): none of those can ever produce a non-null result here, since
     * the output alphabet is a strict whitelist, not a blacklist of "bad" characters.
     */
    fun sanitize(input: String): String? {
        val stripped = input.trim().replace("-", "").uppercase()
        return if (VALID_CODE.matches(stripped)) stripped else null
    }
}
