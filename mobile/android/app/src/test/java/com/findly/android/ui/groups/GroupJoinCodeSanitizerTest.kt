package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [GroupJoinCodeSanitizer] is the pure gate every group join code passes through before it
 * reaches [com.findly.android.network.ports.GroupsApi.joinGroup] — most importantly the
 * `findly://group-join?code=…` deep link, whose `code` query parameter is untrusted external input
 * (specs/003-android-client.md §12.2). Rules mirror 001-api-contract.md §1.4: 8 chars of Crockford
 * base32 (digits + A-Z minus I/L/O/U), case-insensitive, hyphens ignored.
 */
class GroupJoinCodeSanitizerTest {

    @Test
    fun `an already-canonical 8-char code passes through unchanged`() {
        assertEquals("7F3K9QRZ", GroupJoinCodeSanitizer.sanitize("7F3K9QRZ"))
    }

    @Test
    fun `lowercase input is upper-cased`() {
        assertEquals("7F3K9QRZ", GroupJoinCodeSanitizer.sanitize("7f3k9qrz"))
    }

    @Test
    fun `the display hyphen (XXXX-XXXX) is stripped`() {
        assertEquals("7F3K9QRZ", GroupJoinCodeSanitizer.sanitize("7f3k-9qrz"))
    }

    @Test
    fun `surrounding whitespace is trimmed`() {
        assertEquals("7F3K9QRZ", GroupJoinCodeSanitizer.sanitize("  7F3K9QRZ  "))
    }

    @Test
    fun `excluded Crockford letters (I, L, O, U) are rejected`() {
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3KIQRZ"))
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3KLQRZ"))
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3KOQRZ"))
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3KUQRZ"))
    }

    @Test
    fun `wrong length is rejected`() {
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3K9QR"))
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3K9QRZZ"))
        assertNull(GroupJoinCodeSanitizer.sanitize(""))
    }

    @Test
    fun `untrusted deep-link garbage never validates`() {
        assertNull(GroupJoinCodeSanitizer.sanitize("../../etc/passwd"))
        assertNull(GroupJoinCodeSanitizer.sanitize("<script>alert(1)</script>"))
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3K9QRZ; DROP TABLE groups"))
        assertNull(GroupJoinCodeSanitizer.sanitize("null"))
    }

    @Test
    fun `a code with embedded whitespace is rejected, not silently collapsed`() {
        assertNull(GroupJoinCodeSanitizer.sanitize("7F3K 9QRZ"))
    }
}
