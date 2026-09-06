package com.findly.android.ui.locate

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §5.1 "Requester side": `late` renders "exactly like fresh plus an
 * age caption". Pure so [LocateScreen] can call it without any wall-clock dependency in a test. */
class LocateAgeCaptionTest {

    @Test
    fun `under a minute reads just now`() {
        val now = Instant.parse("2026-09-06T09:10:00Z")
        assertEquals("just now", LocateAgeCaption.forRecordedAt("2026-09-06T09:09:31Z", now))
    }

    @Test
    fun `exactly one minute uses singular wording`() {
        val now = Instant.parse("2026-09-06T09:10:00Z")
        assertEquals("1 minute ago", LocateAgeCaption.forRecordedAt("2026-09-06T09:09:00Z", now))
    }

    @Test
    fun `several minutes uses plural wording`() {
        val now = Instant.parse("2026-09-06T09:10:00Z")
        assertEquals("5 minutes ago", LocateAgeCaption.forRecordedAt("2026-09-06T09:05:00Z", now))
    }

    @Test
    fun `malformed recordedAt yields an empty caption rather than crashing`() {
        assertEquals("", LocateAgeCaption.forRecordedAt("not-a-date", Instant.now()))
    }
}
