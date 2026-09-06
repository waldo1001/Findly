package com.findly.android.location.settings

import com.findly.android.network.DeviceSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §3.2 "Restart and recovery" / §3.5: the idempotent "re-apply the
 * cached schedule" decision behind `AppContainer.reapplyCachedSchedule` — the single entry point
 * cold start, every foreground, and the boot/package-replaced receiver all call. */
class CachedScheduleReapplyDecisionTest {

    @Test
    fun `no cached settings - do nothing`() {
        assertEquals(
            CachedScheduleReapplyDecision.DoNothing,
            CachedScheduleReapplyDecision.decide(null),
        )
    }

    @Test
    fun `tracking paused - do nothing`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 15, trackingEnabled = false)
        assertEquals(
            CachedScheduleReapplyDecision.DoNothing,
            CachedScheduleReapplyDecision.decide(cached),
        )
    }

    @Test
    fun `tracking enabled - reschedule at the cached interval`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 15, trackingEnabled = true)
        assertEquals(
            CachedScheduleReapplyDecision.Reschedule(15),
            CachedScheduleReapplyDecision.decide(cached),
        )
    }
}
