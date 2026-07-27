package com.findly.android.pushmessages

import com.findly.android.fakes.FakeScheduleRebuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.2/§3.5; 001-api-contract.md §8.3 — always the complete current
 * values of both fields, applied idempotently, never as a delta. */
class SettingsChangedPushHandlerTest {

    @Test
    fun `applies both fields from a well-formed payload`() {
        val rebuilder = FakeScheduleRebuilder()

        SettingsChangedPushHandler(rebuilder).handle(
            mapOf("syncIntervalMinutes" to "30", "trackingEnabled" to "false"),
        )

        assertEquals(listOf(30 to false), rebuilder.calls)
    }

    @Test
    fun `applying the identical payload twice is idempotent and reorder-safe`() {
        val rebuilder = FakeScheduleRebuilder()
        val handler = SettingsChangedPushHandler(rebuilder)
        val payload = mapOf("syncIntervalMinutes" to "15", "trackingEnabled" to "true")

        handler.handle(payload)
        handler.handle(payload)

        assertEquals(listOf(15 to true, 15 to true), rebuilder.calls)
    }

    @Test
    fun `missing syncIntervalMinutes drops the payload without crashing`() {
        val rebuilder = FakeScheduleRebuilder()

        SettingsChangedPushHandler(rebuilder).handle(mapOf("trackingEnabled" to "true"))

        assertTrue(rebuilder.calls.isEmpty())
    }

    @Test
    fun `non-numeric syncIntervalMinutes drops the payload without crashing`() {
        val rebuilder = FakeScheduleRebuilder()

        SettingsChangedPushHandler(rebuilder).handle(
            mapOf("syncIntervalMinutes" to "soon", "trackingEnabled" to "true"),
        )

        assertTrue(rebuilder.calls.isEmpty())
    }

    @Test
    fun `missing trackingEnabled drops the payload without crashing`() {
        val rebuilder = FakeScheduleRebuilder()

        SettingsChangedPushHandler(rebuilder).handle(mapOf("syncIntervalMinutes" to "30"))

        assertTrue(rebuilder.calls.isEmpty())
    }

    @Test
    fun `non-boolean trackingEnabled drops the payload without crashing`() {
        val rebuilder = FakeScheduleRebuilder()

        SettingsChangedPushHandler(rebuilder).handle(
            mapOf("syncIntervalMinutes" to "30", "trackingEnabled" to "maybe"),
        )

        assertTrue(rebuilder.calls.isEmpty())
    }
}
