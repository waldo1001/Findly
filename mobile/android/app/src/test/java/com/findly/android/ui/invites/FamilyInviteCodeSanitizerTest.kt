package com.findly.android.ui.invites

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [FamilyInviteCodeSanitizer] is the family-invite twin of
 * [com.findly.android.ui.groups.GroupJoinCodeSanitizer] (specs/010-app-shell-and-screen-ux.md §5,
 * 001-api-contract.md §1.4) — the pure gate every family invite code passes through before it
 * reaches `FamilyApi.acceptInvite`, most importantly the `findly://family-join?code=…` deep
 * link's `code` query parameter and the `https://{JOIN_LINK_HOST}/f#{CODE}` fragment, both
 * untrusted external input (specs/007-public-join-links.md §4). Mirrors
 * `GroupJoinCodeSanitizerTest`'s rigor exactly, since the wire format is byte-for-byte identical.
 */
class FamilyInviteCodeSanitizerTest {

    @Test
    fun `an already-canonical 8-char code passes through unchanged`() {
        assertEquals("7F3K9QRZ", FamilyInviteCodeSanitizer.sanitize("7F3K9QRZ"))
    }

    @Test
    fun `lowercase input is upper-cased`() {
        assertEquals("7F3K9QRZ", FamilyInviteCodeSanitizer.sanitize("7f3k9qrz"))
    }

    @Test
    fun `the display hyphen (XXXX-XXXX) is stripped`() {
        assertEquals("7F3K9QRZ", FamilyInviteCodeSanitizer.sanitize("7f3k-9qrz"))
    }

    @Test
    fun `surrounding whitespace is trimmed`() {
        assertEquals("7F3K9QRZ", FamilyInviteCodeSanitizer.sanitize("  7F3K9QRZ  "))
    }

    @Test
    fun `excluded Crockford letters (I, L, O, U) are rejected`() {
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3KIQRZ"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3KLQRZ"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3KOQRZ"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3KUQRZ"))
    }

    @Test
    fun `wrong length is rejected`() {
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3K9QR"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3K9QRZZ"))
        assertNull(FamilyInviteCodeSanitizer.sanitize(""))
    }

    @Test
    fun `untrusted deep-link garbage never validates`() {
        assertNull(FamilyInviteCodeSanitizer.sanitize("../../etc/passwd"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("<script>alert(1)</script>"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3K9QRZ; DROP TABLE families"))
        assertNull(FamilyInviteCodeSanitizer.sanitize("null"))
    }

    @Test
    fun `a code with embedded whitespace is rejected, not silently collapsed`() {
        assertNull(FamilyInviteCodeSanitizer.sanitize("7F3K 9QRZ"))
    }
}
