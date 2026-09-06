package com.findly.android.pushmessages

/**
 * 001-api-contract.md section 8.1's normative title template, rendered on-device from
 * `data.requestedByName` - the Android `LOCATE_REQUEST` message is data-only on purpose (specs/009
 * section 5.1), so the client (via [com.findly.android.pushmessages.LocateNotifier]) builds this
 * string itself rather than receiving it server-composed the way iOS does in `aps.alert.title`.
 */
object LocateNotificationTitle {

    /** specs/009 section 9 (amended 2026-09-06 - A39's security review): `requestedByName` is
     * another family member's raw, attacker-controlled `displayName` - the backend validates it
     * for length only (1-30), never for character content - rendered straight into an ongoing
     * notification for up to 45 s (section 5.1). Strips bidi override/isolate controls
     * (U+202A-U+202E, U+2066-U+2069, which can visually reverse or hide the rest of the string,
     * including this class's own " is locating you" suffix), collapses newlines and other
     * control characters into a single space so they cannot reflow or truncate the title, and
     * clamps to 30 characters as defence in depth even though the server already enforces that
     * bound. This is a client-side obligation regardless of any server-side hardening.
     *
     * **A39's final round, finding 4 (Minor):** a name made entirely of bidi/control characters
     * (or, per [forRequesterData], one missing from the push data entirely) sanitises down to a
     * blank string - [sanitize] falls back to [PLACEHOLDER_NAME] in that case, rather than
     * rendering the grammatically-broken " is locating you" that used to make an adversarial name
     * indistinguishable from no name having been supplied at all. */
    fun forRequester(requestedByName: String): String = "${sanitize(requestedByName)} is locating you"

    /** specs/009 section 5.1: `requestedByName` may be absent from the push `data` map entirely
     * (never observed in practice, but nothing enforces it) - falls back to the empty string
     * rather than crashing. Shared by all three of A39's handoff branches via [LocateNotifier] so
     * this extraction - the one *decidable* part of what that Android-framework glue does - stays
     * covered by a test even though none of its three real callers
     * ([com.findly.android.queue.worker.LocateForegroundService],
     * [com.findly.android.queue.worker.LocateRequestWorker], and the presence-reuse branch wired
     * in `AppContainer`) are themselves unit-tested. */
    fun forRequesterData(data: Map<String, String>): String = forRequester(data["requestedByName"].orEmpty())

    private val BIDI_CONTROLS = ('\u202A'..'\u202E') + ('\u2066'..'\u2069')
    private const val MAX_NAME_LENGTH = 30

    /** specs/009 section 9 (amended 2026-09-06 - A39's final round, finding 4): used both when
     * [sanitize] strips a supplied name down to nothing and when `requestedByName` is missing from
     * the push data entirely ([forRequesterData]) - the two cases are deliberately
     * indistinguishable in the rendered title, so there is only one fallback string. */
    private const val PLACEHOLDER_NAME = "Someone"

    private fun sanitize(name: String): String {
        val withoutBidi = name.filterNot { it in BIDI_CONTROLS }
        val withoutControls = withoutBidi.map { ch -> if (ch.isISOControl()) ' ' else ch }.joinToString("")
        val collapsed = withoutControls.replace(Regex(" +"), " ").trim()
        if (collapsed.isBlank()) return PLACEHOLDER_NAME
        return clampToCodePoints(collapsed, MAX_NAME_LENGTH)
    }

    /** specs/009 section 9 (amended 2026-09-06 - A39's final round, finding 3): `String.take(n)`
     * counts UTF-16 code units, not characters, so a name whose 30th unit lands on the high
     * surrogate of a supplementary-plane character (e.g. most emoji) used to split it in half,
     * leaving an unpaired surrogate that renders as a replacement glyph. Clamping by code point
     * (via [String.offsetByCodePoints], which always lands on a character boundary) instead of by
     * UTF-16 unit keeps a multi-unit character whole even right at the boundary. */
    private fun clampToCodePoints(value: String, maxCodePoints: Int): String {
        if (value.codePointCount(0, value.length) <= maxCodePoints) return value
        val cutIndex = value.offsetByCodePoints(0, maxCodePoints)
        return value.substring(0, cutIndex)
    }
}
