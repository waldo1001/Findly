package com.findly.android.ui.invites

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [FamilyInviteShareTextBuilder] produces the exact, normative share text of
 * specs/007-public-join-links.md §4 (as amended 2026-08-26) — reproduced byte-for-byte, not
 * paraphrased:
 * ```
 * Join our family on Findly — invite code {XXXX-XXXX}
 * https://{JOIN_LINK_HOST}/f#{CODE}
 * ```
 * where `{XXXX-XXXX}` is the hyphenated display form and the fragment `{CODE}` is canonical
 * (uppercase, no hyphen). Snapshot-tested against a fixed code + host per specs/010-app-shell-and-
 * screen-ux.md §10 ("share text equals the 007 §4 template byte-for-byte").
 */
class FamilyInviteShareTextBuilderTest {

    @Test
    fun `matches the 007 §4 family template byte-for-byte`() {
        val text = FamilyInviteShareTextBuilder.build(joinLinkHost = "findly-join.example.net", code = "7F3K9QRZ")
        assertEquals(
            "Join our family on Findly — invite code 7F3K-9QRZ\n" +
                "https://findly-join.example.net/f#7F3K9QRZ",
            text,
        )
    }

    @Test
    fun `the fragment code is canonical (uppercase, no hyphen) even when the input code is lowercase`() {
        val text = FamilyInviteShareTextBuilder.build(joinLinkHost = "findly-join.example.net", code = "7f3k9qrz")
        assertEquals(
            "Join our family on Findly — invite code 7F3K-9QRZ\n" +
                "https://findly-join.example.net/f#7F3K9QRZ",
            text,
        )
    }

    @Test
    fun `contains no store URL -- the message stays short per 007 §4`() {
        val text = FamilyInviteShareTextBuilder.build(joinLinkHost = "findly-join.example.net", code = "7F3K9QRZ")
        assertEquals(false, text.contains("play.google.com"))
        assertEquals(false, text.contains("apps.apple.com"))
    }
}
