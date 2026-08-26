package com.findly.android.ui.invites

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [FamilyInviteLinkBuilder] builds the canonical family-invite public link
 * (specs/007-public-join-links.md §1 as amended 2026-08-26): `https://{JOIN_LINK_HOST}/f#{CODE}`.
 * Mirrors [com.findly.android.ui.groups.GroupJoinLinkBuilderTest] for the `/f` path.
 */
class FamilyInviteLinkBuilderTest {

    @Test
    fun `builds the exact https link with the code in the fragment, never a query parameter`() {
        val link = FamilyInviteLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ")
        assertEquals("https://findly-join.example.net/f#7F3K9QRZ", link)
    }

    @Test
    fun `the code never appears before a query-string marker`() {
        val link = FamilyInviteLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ")
        // The fragment marker '#' must precede the code, and no '?' may appear at all — a code
        // in a query string would be sent to the server/CDN/proxy and logged (007 §1's load-
        // bearing privacy property).
        assertEquals(-1, link.indexOf('?'))
        assertEquals("https://findly-join.example.net/f", link.substringBefore('#'))
    }
}
