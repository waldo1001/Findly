package com.findly.android.queue.worker

import com.findly.android.network.DeviceSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §3.2 "Restart and recovery": a `START_STICKY` OS restart delivers
 * a **null** `Intent` to `LocationForegroundService.onStartCommand` — this is the pure decision
 * behind what it does about that, independent of any `Service`/`Context`. */
class ServiceRestartDecisionTest {

    @Test
    fun `empty cache - stop`() {
        assertEquals(ServiceRestartDecision.Stop, ServiceRestartDecision.decide(null))
    }

    @Test
    fun `paused cache - stop, even at a foreground-service interval`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 5, trackingEnabled = false)
        assertEquals(ServiceRestartDecision.Stop, ServiceRestartDecision.decide(cached))
    }

    @Test
    fun `tracking enabled at a foreground-service interval - start the loop with the cached interval`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 5, trackingEnabled = true)
        assertEquals(
            ServiceRestartDecision.StartWithInterval(5),
            ServiceRestartDecision.decide(cached),
        )
    }

    @Test
    fun `tracking enabled but the cached interval is not a foreground-service interval - stop`() {
        // SyncStrategySelector.strategyFor(15) is currently WorkManager, not ForegroundService
        // (SyncStrategySelectorTest) - the decision is expressed against the selector rather than
        // a hardcoded threshold so it stays correct once A41 changes that boundary.
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 15, trackingEnabled = true)
        assertEquals(ServiceRestartDecision.Stop, ServiceRestartDecision.decide(cached))
    }

    @Test
    fun `tracking enabled at a battery-saver interval - stop`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 60, trackingEnabled = true)
        assertEquals(ServiceRestartDecision.Stop, ServiceRestartDecision.decide(cached))
    }
}
