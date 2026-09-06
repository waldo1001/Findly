package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    // specs/009-device-runtime.md section 9 (amended 2026-09-06 - A39's final round, finding 3):
    // `take(30)` counts UTF-16 code units, not characters. A name of 29 BMP characters followed by
    // an emoji is 31 UTF-16 units (29 + 2 for the surrogate pair), so the old clamp kept the
    // emoji's lone high surrogate and dropped its low surrogate - an unpaired surrogate that
    // renders as a replacement glyph. The existing emoji test above uses a short name (well under
    // 30) and the existing boundary test uses plain ASCII, so neither combination ever exercised
    // this. The fix must clamp on code points, so the boundary case below keeps the emoji whole.

    @Test
    fun `clamping at the boundary does not split a trailing emoji's surrogate pair`() {
        val twentyNineChars = "A".repeat(29)
        // U+1F389 (party popper), written as its UTF-16 surrogate pair (same character as the
        // "leaves an emoji ... untouched" test above) - 29 chars + 1 emoji = 30 code points but
        // 31 UTF-16 units.
        val emoji = "\uD83C\uDF89"
        val nameWithTrailingEmoji = twentyNineChars + emoji
        val title = LocateNotificationTitle.forRequester(nameWithTrailingEmoji)

        assertEquals("$twentyNineChars$emoji is locating you", title)
        assertFalse("title must not contain an unpaired (lone) surrogate", title.hasUnpairedSurrogate())
    }

    private fun String.hasUnpairedSurrogate(): Boolean {
        var i = 0
        while (i < length) {
            val ch = this[i]
            when {
                Character.isHighSurrogate(ch) -> {
                    val hasLow = i + 1 < length && Character.isLowSurrogate(this[i + 1])
                    if (!hasLow) return true
                    i += 2
                }
                Character.isLowSurrogate(ch) -> return true // a low surrogate with no preceding high one
                else -> i += 1
            }
        }
        return false
    }

    // specs/009-device-runtime.md section 9 (amended 2026-09-06 - A39's final round, finding 4):
    // the server validates `displayName` for length only (1-30), never for character content, so
    // a name made entirely of bidi/control characters sanitises down to "" and the title becomes
    // a bare " is locating you" - indistinguishable from the no-name-supplied fallback below, even
    // though a name genuinely was supplied. Chosen fix: route both the missing-field case and the
    // sanitised-to-blank case to the same "Someone" placeholder, so the title is always a complete
    // sentence and the two cases don't need to be told apart.

    @Test
    fun `a name that sanitises down to blank falls back to the generic placeholder`() {
        // Entirely bidi override/isolate controls (U+202E RLO, U+2066 LRI, U+2069 PDI, same
        // characters as the security-review tests above) - every character is stripped by
        // sanitize(), leaving "".
        assertEquals(
            "Someone is locating you",
            LocateNotificationTitle.forRequester("\u202E\u2066\u2069"),
        )
    }

    @Test
    fun `a name of only whitespace and control characters falls back to the generic placeholder`() {
        assertEquals(
            "Someone is locating you",
            LocateNotificationTitle.forRequester("  \n "),
        )
    }

    // specs/009-device-runtime.md section 5.1: requestedByName may be absent from the push data
    // map (never observed in practice, nothing enforces it) - shared by all three A39 handoff
    // branches via the new LocateNotifier (finding 1), which delegates the missing-field default
    // here so it stays covered even though none of its three Android callers are themselves
    // unit-tested (finding 11, A39 review). Finding 4 (A39's final round) routes this case to the
    // same "Someone" placeholder as a sanitised-to-blank supplied name, rather than leaving it as
    // the previous, grammatically-broken " is locating you".

    @Test
    fun `forRequesterData reads requestedByName out of the push data map`() {
        assertEquals(
            "Eric is locating you",
            LocateNotificationTitle.forRequesterData(mapOf("requestedByName" to "Eric")),
        )
    }

    @Test
    fun `forRequesterData falls back to the generic placeholder when requestedByName is missing`() {
        assertEquals("Someone is locating you", LocateNotificationTitle.forRequesterData(emptyMap()))
    }
}
