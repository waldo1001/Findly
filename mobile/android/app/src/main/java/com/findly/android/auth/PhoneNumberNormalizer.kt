package com.findly.android.auth

/**
 * Pure E.164 phone-number normalizer (specs/006-phone-auth.md §3), applied to user input before
 * any provider call. Identical rules to the iOS `PhoneNumberNormalizer` (specs/004 §4) — kept as
 * a plain `object` (no Android framework import) so it's trivially unit-testable and reusable
 * from [DevAuthProvider]/`SignInStateHolder` without any dependency.
 */
object PhoneNumberNormalizer {

    /** Strips spaces, dashes, dots, and parentheses (§3.1) before the prefix rules apply. */
    private val SEPARATORS = Regex("[\\s()\\-.]")

    /** E.164: `+` then a non-zero digit, then 6–14 more digits (§3.4) — 7–15 digits total. */
    private val E164 = Regex("^\\+[1-9]\\d{6,14}$")

    /**
     * Returns the normalized E.164 number, or `null` if the input can't be normalized into one
     * (§3.4) — callers MUST surface `INVALID_PHONE_NUMBER` and make **no provider call** when
     * this returns `null` (006 §4.1's "invalid → EnteringPhone(error) [no provider call]").
     */
    fun normalize(input: String): String? {
        val stripped = input.replace(SEPARATORS, "")
        val prefixed = when {
            // §3.2: a leading "00" (international dialing prefix) becomes "+".
            stripped.startsWith("00") -> "+" + stripped.substring(2)
            // Already has a country code prefix — left untouched.
            stripped.startsWith("+") -> stripped
            // §3.3: a leading single "0" with no "+" becomes "+32" + rest (Belgium-centric default).
            stripped.startsWith("0") -> "+32" + stripped.substring(1)
            else -> stripped
        }
        return if (E164.matches(prefixed)) prefixed else null
    }
}
