package com.findly.android.queue.worker

import org.junit.Assert.assertEquals
import org.junit.Test

class SyncStrategySelectorTest {

    @Test
    fun `5 and 10 minutes use the foreground service`() {
        assertEquals(SyncStrategy.ForegroundService(5), SyncStrategySelector.strategyFor(5))
        assertEquals(SyncStrategy.ForegroundService(10), SyncStrategySelector.strategyFor(10))
    }

    @Test
    fun `15, 30, 60, 120 and 1440 use WorkManager`() {
        for (interval in listOf(15, 30, 60, 120, 1440)) {
            assertEquals(SyncStrategy.WorkManager(interval), SyncStrategySelector.strategyFor(interval))
        }
    }
}
