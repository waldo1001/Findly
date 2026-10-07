package com.findly.android.pendinglink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** specs/010 §1.3 "Capture": every incoming join/invite link goes through the 007 parsers first.
 * [JoinLinkParser] is the single entry that recognises all four 007 §1/§4 forms. Codes here are the
 * obviously-fictional `7F3K9QRZ` class (007 §7 capability hygiene). */
class JoinLinkParserTest {

    private val host = "findly-join.example.net"

    private fun https(path: String?, fragment: String?, scheme: String = "https", h: String? = host) =
        JoinLinkParser.parse(
            scheme = scheme, host = h, path = path, fragment = fragment, codeQueryParam = null, joinLinkHost = host,
        )

    private fun custom(h: String?, code: String?, scheme: String = "findly") =
        JoinLinkParser.parse(
            scheme = scheme, host = h, path = null, fragment = null, codeQueryParam = code, joinLinkHost = host,
        )

    @Test
    fun `https g link with a canonical fragment is a group join with the sanitized code`() {
        assertEquals(IncomingLink(PendingLinkKind.GroupJoin, "7F3K9QRZ"), https("/g", "7F3K9QRZ"))
    }

    @Test
    fun `https f link with a hyphenated lowercase fragment is a family invite, normalized`() {
        assertEquals(IncomingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ"), https("/f", "7f3k-9qrz"))
    }

    @Test
    fun `findly group-join custom-scheme link carries the code in the query parameter`() {
        assertEquals(IncomingLink(PendingLinkKind.GroupJoin, "7F3K9QRZ"), custom("group-join", "7f3k-9qrz"))
    }

    @Test
    fun `findly family-join custom-scheme link is a family invite`() {
        assertEquals(IncomingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ"), custom("family-join", "7F3K9QRZ"))
    }

    @Test
    fun `a matching link without a usable code parses with a null code (join screen, no prefill)`() {
        assertEquals(IncomingLink(PendingLinkKind.GroupJoin, null), https("/g", null))
        assertEquals(IncomingLink(PendingLinkKind.FamilyInvite, null), https("/f", "not a code"))
        assertEquals(IncomingLink(PendingLinkKind.GroupJoin, null), custom("group-join", null))
        assertEquals(IncomingLink(PendingLinkKind.FamilyInvite, null), custom("family-join", "XX"))
    }

    @Test
    fun `wrong host, wrong path and wrong scheme are not join links`() {
        assertNull(https("/g", "7F3K9QRZ", h = "evil.example.net"))
        assertNull(https("/x", "7F3K9QRZ"))
        assertNull(https("/g", "7F3K9QRZ", scheme = "http"))
        assertNull(custom("elsewhere", "7F3K9QRZ"))
        assertNull(custom("group-join", "7F3K9QRZ", scheme = "other"))
    }

    @Test
    fun `no uri at all is not a join link`() {
        assertNull(
            JoinLinkParser.parse(
                scheme = null, host = null, path = null, fragment = null, codeQueryParam = null, joinLinkHost = host,
            ),
        )
    }
}
