package com.findly.android.ui.invites

import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [InviteExpiryFormatter] renders the create-invite success view's "Expires {local date/time}"
 * line (specs/010-app-shell-and-screen-ux.md §5.1) from the server's `expiresAt` response field —
 * **never** a client-computed `now + 72h` (the task brief's explicit caution: 72 h is what the
 * server implements, not a client constant; only the static caption sentence quotes that policy
 * as design copy, the actual displayed moment always comes from the wire value). [zoneId] is an
 * explicit parameter (defaulting to the device's own [java.time.ZoneId.systemDefault]) purely so
 * this is deterministic under test — the real call site never passes it, letting the formatter
 * convert the UTC wire timestamp into the phone's own local time zone, which is the "local" in
 * "local date/time".
 */
class InviteExpiryFormatterTest {

    @Test
    fun `converts the UTC wire timestamp into the given local time zone`() {
        // 2026-07-22T10:00:00Z is deep European summer (CEST, UTC+2) in Europe/Brussels.
        val formatted = InviteExpiryFormatter.formatExpiresAt("2026-07-22T10:00:00Z", ZoneId.of("Europe/Brussels"))
        assertEquals("22 Jul 2026, 12:00", formatted)
    }

    @Test
    fun `a different time zone renders a different wall-clock time for the same instant`() {
        val formatted = InviteExpiryFormatter.formatExpiresAt("2026-07-22T10:00:00Z", ZoneId.of("America/New_York"))
        // 2026-07-22 is within US Eastern Daylight Time (UTC-4).
        assertEquals("22 Jul 2026, 06:00", formatted)
    }

    @Test
    fun `never derives from the current time -- purely a function of the given instant`() {
        val a = InviteExpiryFormatter.formatExpiresAt("2026-07-22T10:00:00Z", ZoneId.of("UTC"))
        val b = InviteExpiryFormatter.formatExpiresAt("2026-07-22T10:00:00Z", ZoneId.of("UTC"))
        assertEquals(a, b)
        assertEquals("22 Jul 2026, 10:00", a)
    }
}
