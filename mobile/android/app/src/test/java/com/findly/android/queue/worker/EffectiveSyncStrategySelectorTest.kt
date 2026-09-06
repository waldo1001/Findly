package com.findly.android.queue.worker

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * specs/009-device-runtime.md §3.2: "It MUST be started only when `syncIntervalMinutes` ∈
 * {5, 10, 15, 30} **and** `ACCESS_BACKGROUND_LOCATION` is granted... Without background
 * permission the device falls back to §3.1 WorkManager for its interval." [SyncStrategySelector]
 * alone can't express this (it has no permission input by design, so
 * [ServiceRestartDecision] stays unchanged) — this is the pure policy that layers the fallback on
 * top.
 */
class EffectiveSyncStrategySelectorTest {

    @Test
    fun `5, 10, 15 and 30 minutes use the foreground service when background permission is granted`() {
        for (interval in listOf(5, 10, 15, 30)) {
            assertEquals(
                "interval $interval",
                SyncStrategy.ForegroundService(interval),
                EffectiveSyncStrategySelector.strategyFor(interval, backgroundLocationGranted = true),
            )
        }
    }

    @Test
    fun `5, 10, 15 and 30 minutes fall back to WorkManager when background permission is not granted`() {
        for (interval in listOf(5, 10, 15, 30)) {
            assertEquals(
                "interval $interval",
                SyncStrategy.WorkManager(interval),
                EffectiveSyncStrategySelector.strategyFor(interval, backgroundLocationGranted = false),
            )
        }
    }

    @Test
    fun `60, 120 and 1440 minutes always use WorkManager, regardless of background permission`() {
        for (interval in listOf(60, 120, 1440)) {
            assertEquals(
                "interval $interval, granted",
                SyncStrategy.WorkManager(interval),
                EffectiveSyncStrategySelector.strategyFor(interval, backgroundLocationGranted = true),
            )
            assertEquals(
                "interval $interval, not granted",
                SyncStrategy.WorkManager(interval),
                EffectiveSyncStrategySelector.strategyFor(interval, backgroundLocationGranted = false),
            )
        }
    }
}
