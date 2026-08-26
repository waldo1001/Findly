package com.findly.android.ui.invites

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [FamilyInviteHttpsLinkParser] is the family-invite twin of
 * [com.findly.android.ui.groups.GroupJoinHttpsLinkParser] (specs/007-public-join-links.md §1/§4
 * as amended 2026-08-26, specs/010-app-shell-and-screen-ux.md §5.2): the gate every incoming
 * `https://{host}/f#{code}` `Intent` `Uri` passes through before
 * [com.findly.android.MainActivity] ever considers navigating to the accept-invite screen. Mirrors
 * `GroupJoinHttpsLinkParserTest`'s rigor for the `/f` path instead of `/g`.
 */
class FamilyInviteHttpsLinkParserTest {

    private val host = "findly-join.example.net"

    @Test
    fun `a well-formed link with a canonical fragment matches and sanitizes the code`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", host, "/f", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `the hyphenated display form is normalized identically to the deep-link path`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", host, "/f", "7f3k-9qrz", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `wrong host is ignored, never mis-routed`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", "evil.example.net", "/f", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `the group path (g) is never treated as the family path (f)`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", host, "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `wrong path is ignored`() {
        assertEquals(
            FamilyInviteHttpsLinkParser.Result.NoMatch,
            FamilyInviteHttpsLinkParser.parse("https", host, "/other", "7F3K9QRZ", joinLinkHost = host),
        )
        assertEquals(
            FamilyInviteHttpsLinkParser.Result.NoMatch,
            FamilyInviteHttpsLinkParser.parse("https", host, "/f/", "7F3K9QRZ", joinLinkHost = host),
        )
        assertEquals(
            FamilyInviteHttpsLinkParser.Result.NoMatch,
            FamilyInviteHttpsLinkParser.parse("https", host, null, "7F3K9QRZ", joinLinkHost = host),
        )
    }

    @Test
    fun `wrong scheme is ignored (http, not https)`() {
        val result = FamilyInviteHttpsLinkParser.parse("http", host, "/f", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `null host is ignored`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", null, "/f", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `a matching host and path with a null fragment opens with no prefill, not an error`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", host, "/f", null, joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.Matched(null), result)
    }

    @Test
    fun `a matching host and path with an unparsable fragment opens with no prefill, not an error`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", host, "/f", "<script>alert(1)</script>", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.Matched(null), result)
    }

    @Test
    fun `scheme and host comparison is case-insensitive`() {
        val result = FamilyInviteHttpsLinkParser.parse("HTTPS", host.uppercase(), "/f", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `path comparison is case-sensitive`() {
        val result = FamilyInviteHttpsLinkParser.parse("https", host, "/F", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(FamilyInviteHttpsLinkParser.Result.NoMatch, result)
    }

    // --- parseIfFreshLaunch — mirrors GroupJoinHttpsLinkParser's rotation/recreation guard. ---

    @Test
    fun `not a fresh launch yields NoMatch even for an otherwise well-formed matching link`() {
        val result = FamilyInviteHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = false,
            scheme = "https",
            host = host,
            path = "/f",
            fragment = "7F3K9QRZ",
            joinLinkHost = host,
        )
        assertEquals(FamilyInviteHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `a fresh launch behaves exactly like parse for a matching link`() {
        val result = FamilyInviteHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = true,
            scheme = "https",
            host = host,
            path = "/f",
            fragment = "7F3K9QRZ",
            joinLinkHost = host,
        )
        assertEquals(FamilyInviteHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }
}
