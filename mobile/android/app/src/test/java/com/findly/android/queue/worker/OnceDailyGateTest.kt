package com.findly.android.queue.worker

import java.time.LocalDate
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 000-overview.md §O3: "at least one fix per device-local calendar day... NOT every 24h since
 * last fix". */
class OnceDailyGateTest {
    private val today = LocalDate.of(2026, 7, 19)

    @Test
    fun `skips when a fix already exists for today`() {
        assertTrue(OnceDailyGate.shouldSkipCapture(1440, today, lastCaptureLocalDate = today))
    }

    @Test
    fun `does not skip when the last capture was yesterday, regardless of how many hours ago`() {
        assertFalse(OnceDailyGate.shouldSkipCapture(1440, today, lastCaptureLocalDate = today.minusDays(1)))
    }

    @Test
    fun `does not skip when there has never been a capture`() {
        assertFalse(OnceDailyGate.shouldSkipCapture(1440, today, lastCaptureLocalDate = null))
    }

    @Test
    fun `never applies to any interval other than 1440`() {
        assertFalse(OnceDailyGate.shouldSkipCapture(15, today, lastCaptureLocalDate = today))
        assertFalse(OnceDailyGate.shouldSkipCapture(60, today, lastCaptureLocalDate = today))
        assertFalse(OnceDailyGate.shouldSkipCapture(120, today, lastCaptureLocalDate = today))
    }
}
