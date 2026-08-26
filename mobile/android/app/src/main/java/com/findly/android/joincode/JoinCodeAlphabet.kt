package com.findly.android.joincode

/**
 * The single, shared home for 001-api-contract.md §1.4's join/invite-code wire format: **8
 * characters of Crockford base32 (digits `0-9` plus `A-Z` minus `I`/`L`/`O`/`U`, to avoid visual
 * ambiguity)**. Canonical form is uppercase, no hyphen; clients MAY display/accept the
 * `XXXX-XXXX` grouping and the server ignores case/hyphens.
 *
 * This rule is identical for **group join codes** ([com.findly.android.ui.groups.GroupJoinCodeSanitizer])
 * and **family invite codes** ([com.findly.android.ui.invites.FamilyInviteCodeSanitizer]) — both
 * are the exact same 001 §1.4 format, just used for two different endpoints (multi-use group
 * codes, §12.6; single-use family invites, §3.3/§3.4). Extracted here (A36, specs/010-app-shell-
 * and-screen-ux.md §5) so the two sanitizers, and the family invite screen's live-typing smart-
 * field formatter ([com.findly.android.ui.invites.InviteCodeFieldFormatter]), share one spelling
 * of the alphabet rather than three copies that could silently drift out of sync.
 */
object JoinCodeAlphabet {

    /** Crockford base32 alphabet, excluding I/L/O/U (001 §1.4) — the one place this literal is
     * spelled out. Digits first, then letters, so the exclusions read clearly against the full
     * A-Z run they're carved out of. */
    const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    private val ALLOWED_CHARS: Set<Char> = ALPHABET.toSet()

    /** Exactly 8 characters of [ALPHABET] — no more, no less. None of [ALPHABET]'s characters are
     * regex metacharacters, so it can be spliced into a character class as-is. */
    val CODE_REGEX = Regex("^[$ALPHABET]{8}$")

    /**
     * Strips surrounding whitespace and the display hyphen, upper-cases, then validates against
     * the closed 8-char alphabet. Returns `null` for anything that doesn't normalize into a
     * well-formed code — including embedded whitespace, wrong length, excluded letters, or
     * arbitrary untrusted text: none of those can ever produce a non-null result here, since the
     * output alphabet is a strict whitelist, not a blacklist of "bad" characters.
     */
    fun sanitize(input: String): String? {
        val stripped = input.trim().replace("-", "").uppercase()
        return if (CODE_REGEX.matches(stripped)) stripped else null
    }

    /**
     * Upper-cases [input] and drops every character not in [ALPHABET] — used by a *live-typing*
     * field formatter (unlike [sanitize], this never rejects a whole string; it silently filters
     * it down to what the alphabet allows, so a field can format progressively as the user types
     * rather than waiting for a complete, valid code).
     */
    fun filterToAlphabet(input: String): String = input.uppercase().filter { it in ALLOWED_CHARS }

    /** Hyphenated display form (`XXXX-XXXX`, 001 §1.4) of an already-sanitized 8-char code. */
    fun toDisplayForm(sanitized: String): String {
        require(sanitized.length == 8) { "expects an 8-char sanitized code, got \"$sanitized\"" }
        return "${sanitized.substring(0, 4)}-${sanitized.substring(4)}"
    }
}
