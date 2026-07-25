package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [GroupJoinLinkBuilder] produces the exact specs/007-public-join-links.md §1 link shape:
 * `https://{host}/g#{code}`. The code MUST land in the fragment, never a query parameter —
 * asserted explicitly below since that's this design's load-bearing privacy property (007 §1: a
 * fragment is never sent to a server/CDN/proxy, so the capability never appears in a log).
 */
class GroupJoinLinkBuilderTest {

    @Test
    fun `builds the exact 007 section 1 link format`() {
        assertEquals(
            "https://findly-join.example.net/g#7F3K9QRZ",
            GroupJoinLinkBuilder.buildHttpsLink("findly-join.example.net", "7F3K9QRZ"),
        )
    }

    @Test
    fun `the code is carried in the fragment, never as a query parameter`() {
        val link = GroupJoinLinkBuilder.buildHttpsLink("host.example.net", "AAAAAAAA")
        assertEquals(-1, link.indexOf('?'))
        assertEquals(1, link.count { it == '#' })
        assertEquals("AAAAAAAA", link.substringAfter('#'))
    }

    @Test
    fun `path is always exactly slash-g regardless of host`() {
        val link = GroupJoinLinkBuilder.buildHttpsLink("another-host.example.net", "ZZZZZZZZ")
        assertEquals("https://another-host.example.net/g#ZZZZZZZZ", link)
    }
}
