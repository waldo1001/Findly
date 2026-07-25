package com.findly.android.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Pure E.164 normalization rules (specs/006-phone-auth.md §3, test checklist §10). No literal
 * real-looking phone number ever appears here — only the fictional `+3247000000x` family
 * (docs/security-review-checklist.md). */
class PhoneNumberNormalizerTest {

    @Test
    fun `separators - spaces dashes dots and parentheses - are stripped`() {
        assertEquals("+32470000001", PhoneNumberNormalizer.normalize("+32 470-00.00(01)"))
    }

    @Test
    fun `a leading 00 becomes a plus`() {
        assertEquals("+32470000001", PhoneNumberNormalizer.normalize("0032470000001"))
    }

    @Test
    fun `a leading single 0 with no plus becomes plus32`() {
        assertEquals("+32470000001", PhoneNumberNormalizer.normalize("0470000001"))
    }

    @Test
    fun `input already starting with plus is left untouched (aside from separators)`() {
        assertEquals("+32470000001", PhoneNumberNormalizer.normalize("+32470000001"))
        assertEquals("+14155550002", PhoneNumberNormalizer.normalize("+14155550002"))
    }

    @Test
    fun `valid E164 numbers at the length boundaries are accepted`() {
        // 7 digits total after the +: minimum length (1 + 6).
        assertEquals("+1234567", PhoneNumberNormalizer.normalize("+1234567"))
        // 15 digits total after the +: maximum length (1 + 14).
        assertEquals("+123456789012345", PhoneNumberNormalizer.normalize("+123456789012345"))
    }

    @Test
    fun `too short after normalization is rejected`() {
        assertNull(PhoneNumberNormalizer.normalize("+123456"))
    }

    @Test
    fun `too long after normalization is rejected`() {
        assertNull(PhoneNumberNormalizer.normalize("+1234567890123456"))
    }

    @Test
    fun `a leading zero immediately after the plus is rejected (not a valid E164 country code)`() {
        assertNull(PhoneNumberNormalizer.normalize("+0470000001"))
    }

    @Test
    fun `letters or other non-digit characters are rejected`() {
        assertNull(PhoneNumberNormalizer.normalize("+32abc0000001"))
    }

    @Test
    fun `blank input is rejected`() {
        assertNull(PhoneNumberNormalizer.normalize(""))
        assertNull(PhoneNumberNormalizer.normalize("   "))
    }

    @Test
    fun `bare digits with no plus and no leading zero are rejected (no country-code guess beyond the 0-to-plus32 rule)`() {
        assertNull(PhoneNumberNormalizer.normalize("32470000001"))
    }
}
