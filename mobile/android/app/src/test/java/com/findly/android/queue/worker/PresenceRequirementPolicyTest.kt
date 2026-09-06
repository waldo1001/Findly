package com.findly.android.queue.worker

import com.findly.android.network.DeviceSettingsSnapshot
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/009-device-runtime.md §3.2/§7, 000 §D19: [PresenceRequirementPolicy] is the sole gate on
 * the §3.2 "explain and offer" MUST — code-review fix (A41 round 2 finding 8) extracting it out
 * of the previously-untested `AppContainer.presenceCurrentlyRequired`.
 */
class PresenceRequirementPolicyTest {

    @Test
    fun `no cached settings - not required`() {
        assertFalse(PresenceRequirementPolicy.decide(cached = null, backgroundLocationGranted = true))
    }

    @Test
    fun `paused device - not required, even at a presence interval with permission granted`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 5, trackingEnabled = false)
        assertFalse(PresenceRequirementPolicy.decide(cached, backgroundLocationGranted = true))
    }

    @Test
    fun `tracking enabled, presence interval, permission granted - required`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 15, trackingEnabled = true)
        assertTrue(PresenceRequirementPolicy.decide(cached, backgroundLocationGranted = true))
    }

    @Test
    fun `tracking enabled, presence interval, permission NOT granted - not required (falls back to WorkManager)`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 15, trackingEnabled = true)
        assertFalse(PresenceRequirementPolicy.decide(cached, backgroundLocationGranted = false))
    }

    @Test
    fun `tracking enabled, battery-saver interval - not required regardless of permission`() {
        val cached = DeviceSettingsSnapshot(syncIntervalMinutes = 60, trackingEnabled = true)
        assertFalse(PresenceRequirementPolicy.decide(cached, backgroundLocationGranted = true))
    }
}
