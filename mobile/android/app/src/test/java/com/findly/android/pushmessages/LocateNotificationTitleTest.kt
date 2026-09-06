package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Test

/** 001-api-contract.md section 8.1's normative title template, rendered on-device from
 * `data.requestedByName` on Android (the FCM message itself is data-only, specs/009 section 5.1). */
class LocateNotificationTitleTest {

    @Test
    fun `renders the exact normative template`() {
        assertEquals("Eric is locating you", LocateNotificationTitle.forRequester("Eric"))
    }

    @Test
    fun `works for any display name without extra formatting`() {
        assertEquals("Noor is locating you", LocateNotificationTitle.forRequester("Noor"))
    }

    // specs/009-device-runtime.md section 9 (amended 2026-09-06 - A39's security review):
    // requestedByName is another family member's raw displayName, server-validated for length
    // only (1-30) - never for character content - and rendered straight into an ongoing
    // notification for up to 45s. These adversarial cases were the security review's finding:
    // both existing tests above only ever used plain ASCII. Every control/bidi character below
    // is written as an explicit unicode escape so the source file itself stays plain ASCII.

    @Test
    fun `strips a right-to-left override control before rendering the title`() {
        // U+202E (RLO) would otherwise visually reverse everything that follows it, including
        // the literal " is locating you" suffix this class appends.
        assertEquals("cirE is locating you", LocateNotificationTitle.forRequester("\u202EcirE"))
    }

    @Test
    fun `strips bidi isolate controls too`() {
        // U+2066 (LRI) / U+2069 (PDI).
        assertEquals("Eric is locating you", LocateNotificationTitle.forRequester("\u2066Eric\u2069"))
    }

    @Test
    fun `collapses an embedded newline instead of letting it reflow the notification`() {
        assertEquals("Eric X is locating you", LocateNotificationTitle.forRequester("Eric\nX"))
    }

    @Test
    fun `collapses other embedded control characters`() {
        // U+0007 (BEL) - an arbitrary non-newline C0 control character.
        assertEquals("Eric X is locating you", LocateNotificationTitle.forRequester("Eric\u0007X"))
    }

    @Test
    fun `leaves an emoji in the display name untouched`() {
        // U+1F389 (party popper), written as its UTF-16 surrogate pair.
        assertEquals("Eric\uD83C\uDF89 is locating you", LocateNotificationTitle.forRequester("Eric\uD83C\uDF89"))
    }

    @Test
    fun `clamps a name at exactly the 30-character boundary`() {
        val thirtyChars = "A".repeat(30)
        val thirtyOneChars = thirtyChars + "B"
        assertEquals("$thirtyChars is locating you", LocateNotificationTitle.forRequester(thirtyOneChars))
        // The boundary itself (exactly 30) must not be truncated further.
        assertEquals("$thirtyChars is locating you", LocateNotificationTitle.forRequester(thirtyChars))
    }

    // specs/009-device-runtime.md section 5.1: requestedByName may be absent from the push data
    // map (never observed in practice, nothing enforces it) - shared by all three A39 handoff
    // branches via the new LocateNotifier (finding 1), which delegates the missing-field default
    // here so it stays covered even though none of its three Android callers are themselves
    // unit-tested (finding 11, A39 review).

    @Test
    fun `forRequesterData reads requestedByName out of the push data map`() {
        assertEquals(
            "Eric is locating you",
            LocateNotificationTitle.forRequesterData(mapOf("requestedByName" to "Eric")),
        )
    }

    @Test
    fun `forRequesterData falls back to the empty string when requestedByName is missing`() {
        assertEquals(" is locating you", LocateNotificationTitle.forRequesterData(emptyMap()))
    }
}
