package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Test

/** [GroupCountdownFormatter] renders the `FindlyCard`'s countdown-to-`endsAt` text
 * (specs/003-android-client.md §12.2). Pure — takes `now` explicitly so it's deterministic under
 * test (no `Instant.now()` inside the function under test). */
class GroupCountdownFormatterTest {

    private val now = "2026-07-21T10:00:00Z"

    @Test
    fun `several days out renders a day-and-hour countdown`() {
        // now + 2d3h
        assertEquals("2d 3h left", GroupCountdownFormatter.format("2026-07-23T13:00:00Z", now))
    }

    @Test
    fun `less than a day out renders hours and minutes`() {
        assertEquals("3h 30m left", GroupCountdownFormatter.format("2026-07-21T13:30:00Z", now))
    }

    @Test
    fun `less than an hour out renders minutes only`() {
        assertEquals("45m left", GroupCountdownFormatter.format("2026-07-21T10:45:00Z", now))
    }

    @Test
    fun `already past endsAt renders Ended`() {
        assertEquals("Ended", GroupCountdownFormatter.format("2026-07-20T10:00:00Z", now))
        assertEquals("Ended", GroupCountdownFormatter.format(now, now))
    }
}
