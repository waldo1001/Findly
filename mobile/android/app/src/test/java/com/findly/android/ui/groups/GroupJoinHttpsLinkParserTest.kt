package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [GroupJoinHttpsLinkParser] is the gate every incoming `https://{host}/g#{code}` `Intent` `Uri`
 * passes through (specs/007-public-join-links.md §1/§4, specs/003-android-client.md §12.3) before
 * [com.findly.android.MainActivity] ever considers navigating to
 * [com.findly.android.ui.nav.Destinations.GroupJoin]. Mirrors
 * [GroupJoinCodeSanitizerTest]'s rigor for the sibling `findly://` deep link.
 */
class GroupJoinHttpsLinkParserTest {

    private val host = "findly-join.example.net"

    @Test
    fun `a well-formed link with a canonical fragment matches and sanitizes the code`() {
        val result = GroupJoinHttpsLinkParser.parse("https", host, "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `the hyphenated display form is normalized identically to the deep-link path`() {
        val result = GroupJoinHttpsLinkParser.parse("https", host, "/g", "7f3k-9qrz", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `wrong host is ignored, never mis-routed`() {
        val result = GroupJoinHttpsLinkParser.parse("https", "evil.example.net", "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `a host that merely contains the real host as a substring is ignored`() {
        val result = GroupJoinHttpsLinkParser.parse("https", "evil-$host.attacker.net", "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `wrong path is ignored`() {
        assertEquals(
            GroupJoinHttpsLinkParser.Result.NoMatch,
            GroupJoinHttpsLinkParser.parse("https", host, "/other", "7F3K9QRZ", joinLinkHost = host),
        )
        assertEquals(
            GroupJoinHttpsLinkParser.Result.NoMatch,
            GroupJoinHttpsLinkParser.parse("https", host, "/g/", "7F3K9QRZ", joinLinkHost = host),
        )
        assertEquals(
            GroupJoinHttpsLinkParser.Result.NoMatch,
            GroupJoinHttpsLinkParser.parse("https", host, null, "7F3K9QRZ", joinLinkHost = host),
        )
    }

    @Test
    fun `wrong scheme is ignored (http, not https)`() {
        val result = GroupJoinHttpsLinkParser.parse("http", host, "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `the findly custom scheme is ignored by this parser (handled separately)`() {
        val result = GroupJoinHttpsLinkParser.parse("findly", "group-join", null, null, joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `null host is ignored`() {
        val result = GroupJoinHttpsLinkParser.parse("https", null, "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `a matching host and path with a null fragment opens with no prefill, not an error`() {
        val result = GroupJoinHttpsLinkParser.parse("https", host, "/g", null, joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.Matched(null), result)
    }

    @Test
    fun `a matching host and path with an unparsable fragment opens with no prefill, not an error`() {
        val result = GroupJoinHttpsLinkParser.parse("https", host, "/g", "<script>alert(1)</script>", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.Matched(null), result)
    }

    @Test
    fun `scheme and host comparison is case-insensitive`() {
        val result = GroupJoinHttpsLinkParser.parse("HTTPS", host.uppercase(), "/g", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `path comparison is case-sensitive`() {
        val result = GroupJoinHttpsLinkParser.parse("https", host, "/G", "7F3K9QRZ", joinLinkHost = host)
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    // --- parseIfFreshLaunch (code review fix, 2026-07-22): MainActivity recreation on rotation/
    // dark-light toggle/multi-window/locale change/process-death restore hands back the SAME
    // launch Uri via a fresh onCreate — these tests prove the recreation case (isFreshLaunch =
    // false) never matches, even for an otherwise-perfectly-well-formed link, closing the "user
    // navigated away from GroupJoin, then rotated, and got yanked back" bug. ---

    @Test
    fun `not a fresh launch yields NoMatch even for an otherwise well-formed matching link`() {
        val result = GroupJoinHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = false,
            scheme = "https",
            host = host,
            path = "/g",
            fragment = "7F3K9QRZ",
            joinLinkHost = host,
        )
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `not a fresh launch yields NoMatch even with no fragment at all (matched-with-empty-prefill would otherwise apply)`() {
        // Isolates the guard itself: host/path match and the fragment is merely absent (the case
        // that would legitimately produce Matched(null) on a fresh launch, per 007 §4's "no usable
        // fragment opens with an empty prefill, no error") — proving NoMatch here is caused by
        // isFreshLaunch = false, not by an unrelated host/path/fragment mismatch.
        val result = GroupJoinHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = false,
            scheme = "https",
            host = host,
            path = "/g",
            fragment = null,
            joinLinkHost = host,
        )
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }

    @Test
    fun `a fresh launch behaves exactly like parse for a matching link`() {
        val result = GroupJoinHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = true,
            scheme = "https",
            host = host,
            path = "/g",
            fragment = "7F3K9QRZ",
            joinLinkHost = host,
        )
        assertEquals(GroupJoinHttpsLinkParser.Result.Matched("7F3K9QRZ"), result)
    }

    @Test
    fun `a fresh launch with a wrong host still yields NoMatch`() {
        val result = GroupJoinHttpsLinkParser.parseIfFreshLaunch(
            isFreshLaunch = true,
            scheme = "https",
            host = "evil.example.net",
            path = "/g",
            fragment = "7F3K9QRZ",
            joinLinkHost = host,
        )
        assertEquals(GroupJoinHttpsLinkParser.Result.NoMatch, result)
    }
}
