package com.findly.android.ui.invites

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [InviteCodeClipboardExtractor] backs the accept-invite screen's explicit-tap "Paste code"
 * affordance (specs/010-app-shell-and-screen-ux.md §5.2: "Pasting an invite *link* extracts the
 * fragment code via the same 007 parsing" — clipboard text may be a bare code, the
 * `https://{JOIN_LINK_HOST}/f#{CODE}` link, or the `findly://family-join?code={CODE}` deep link).
 * Pure and plain-string-based (no `android.net.Uri`) so it is JVM-testable without Robolectric
 * (specs/003-android-client.md §14) — this is a distinct concern from
 * [FamilyInviteHttpsLinkParser], which expects an already-decomposed `Intent` `Uri`'s components;
 * this one has to find the code inside one raw pasted string.
 *
 * The clipboard is read only on the user's own tap (specs/010 §5.2's explicit-action-only rule) —
 * this class has no knowledge of *when* it's called, only of what to do with whatever text it's
 * handed, which is what makes that call-site rule independently auditable.
 */
class InviteCodeClipboardExtractorTest {

    private val host = "findly-join.example.net"

    @Test
    fun `a bare canonical code is extracted directly`() {
        assertEquals("7F3K9QRZ", InviteCodeClipboardExtractor.extract("7F3K9QRZ", joinLinkHost = host))
    }

    @Test
    fun `a bare hyphenated display-form code is normalized`() {
        assertEquals("7F3K9QRZ", InviteCodeClipboardExtractor.extract("7f3k-9qrz", joinLinkHost = host))
    }

    @Test
    fun `the https family-invite link's fragment code is extracted`() {
        assertEquals(
            "7F3K9QRZ",
            InviteCodeClipboardExtractor.extract("https://$host/f#7F3K9QRZ", joinLinkHost = host),
        )
    }

    @Test
    fun `the https link's fragment is normalized (hyphenated, lowercase)`() {
        assertEquals(
            "7F3K9QRZ",
            InviteCodeClipboardExtractor.extract("https://$host/f#7f3k-9qrz", joinLinkHost = host),
        )
    }

    @Test
    fun `the findly family-join deep link's code query parameter is extracted`() {
        assertEquals(
            "7F3K9QRZ",
            InviteCodeClipboardExtractor.extract("findly://family-join?code=7F3K9QRZ", joinLinkHost = host),
        )
    }

    @Test
    fun `surrounding whitespace, such as from a share-sheet message, does not defeat extraction`() {
        assertEquals(
            "7F3K9QRZ",
            InviteCodeClipboardExtractor.extract("  https://$host/f#7F3K9QRZ  ", joinLinkHost = host),
        )
    }

    @Test
    fun `a https link with the wrong host is rejected, not mis-extracted`() {
        assertNull(InviteCodeClipboardExtractor.extract("https://evil.example.net/f#7F3K9QRZ", joinLinkHost = host))
    }

    @Test
    fun `a group join link (g, not f) is rejected -- never cross-extracted`() {
        assertNull(InviteCodeClipboardExtractor.extract("https://$host/g#7F3K9QRZ", joinLinkHost = host))
    }

    @Test
    fun `the group deep link (group-join, not family-join) is rejected`() {
        assertNull(InviteCodeClipboardExtractor.extract("findly://group-join?code=7F3K9QRZ", joinLinkHost = host))
    }

    @Test
    fun `arbitrary clipboard text that is neither a code nor a link yields null`() {
        assertNull(InviteCodeClipboardExtractor.extract("just some random text I copied", joinLinkHost = host))
        assertNull(InviteCodeClipboardExtractor.extract("", joinLinkHost = host))
    }

    @Test
    fun `a well-formed link whose fragment is garbage yields null, not a crash`() {
        assertNull(InviteCodeClipboardExtractor.extract("https://$host/f#<script>", joinLinkHost = host))
    }
}
