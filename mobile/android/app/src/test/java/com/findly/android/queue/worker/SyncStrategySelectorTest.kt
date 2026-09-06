package com.findly.android.queue.worker

import org.junit.Assert.assertEquals
import org.junit.Test

class SyncStrategySelectorTest {

    // specs/009-device-runtime.md §3 "Strategy selection" (amended 2026-09-06, 000 §D19): every
    // one of the seven 001 §1.4 allowed values, explicitly, so a future range change is caught by
    // name rather than by a loop that could silently stop covering a value.
    @Test
    fun `5 minutes uses the foreground service`() {
        assertEquals(SyncStrategy.ForegroundService(5), SyncStrategySelector.strategyFor(5))
    }

    @Test
    fun `10 minutes uses the foreground service`() {
        assertEquals(SyncStrategy.ForegroundService(10), SyncStrategySelector.strategyFor(10))
    }

    @Test
    fun `15 minutes uses the foreground service (widened 2026-09-06, was WorkManager)`() {
        assertEquals(SyncStrategy.ForegroundService(15), SyncStrategySelector.strategyFor(15))
    }

    @Test
    fun `30 minutes uses the foreground service (widened 2026-09-06, was WorkManager)`() {
        assertEquals(SyncStrategy.ForegroundService(30), SyncStrategySelector.strategyFor(30))
    }

    @Test
    fun `60 minutes uses WorkManager`() {
        assertEquals(SyncStrategy.WorkManager(60), SyncStrategySelector.strategyFor(60))
    }

    @Test
    fun `120 minutes uses WorkManager`() {
        assertEquals(SyncStrategy.WorkManager(120), SyncStrategySelector.strategyFor(120))
    }

    @Test
    fun `1440 minutes (once a day) uses WorkManager`() {
        assertEquals(SyncStrategy.WorkManager(1440), SyncStrategySelector.strategyFor(1440))
    }
}
