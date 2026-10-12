package com.findly.android.ui.groups

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant

/** The pure end-date rule shared by [CreateGroupStateHolder] and [GroupDetailStateHolder]
 * (001 §12.1/§12.4, 005 §2.5 item 6). */
class GroupEndsAtValidationTest {

    private val now = 1_784_707_200_000L
    private val hour = 60L * 60 * 1000
    private val day = 24 * hour

    @Test
    fun `below the floor fails`() {
        assertEquals("End time must be at least 1 hour from now", validateEndsAt(now + 59 * 60_000, now, 30))
    }

    @Test
    fun `exactly the floor passes`() {
        assertNull(validateEndsAt(now + hour, now, 30))
    }

    @Test
    fun `above the cap fails, at the cap passes`() {
        assertEquals("That end date is further out than your plan allows", validateEndsAt(now + 30 * day + 1, now, 30))
        assertNull(validateEndsAt(now + 30 * day, now, 30))
    }

    @Test
    fun `null cap means unbounded`() {
        assertNull(validateEndsAt(now + 3650 * day, now, null))
    }

    @Test
    fun `combineDateAndTime puts the UTC time on the picked date`() {
        val midnight = Instant.parse("2026-08-02T00:00:00Z").toEpochMilli()
        assertEquals(Instant.parse("2026-08-02T22:00:00Z").toEpochMilli(), combineDateAndTime(midnight, 22, 0))
    }

    @Test
    fun `combineDateAndTime clamps out-of-range hour and minute`() {
        val midnight = Instant.parse("2026-08-02T00:00:00Z").toEpochMilli()
        assertEquals(Instant.parse("2026-08-02T23:59:00Z").toEpochMilli(), combineDateAndTime(midnight, 99, 99))
    }
}
