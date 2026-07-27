package com.findly.android.location.settings

import com.findly.android.network.DeviceSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

/** Verifies specs/009-device-runtime.md §3.5's settings-change reaction rules in isolation. */
class SettingsChangeDecisionTest {

    @Test
    fun `first-ever settings (previous null, tracking on) rebuilds the schedule and reports RESUME`() {
        val actions = SettingsChangeDecision.decide(null, DeviceSettingsSnapshot(15, true))

        // previous == null is treated as "trackingEnabled changed" (there is no prior state to
        // compare against), so this lands on RESUME rather than NONE - which is actually the
        // spec-correct label: 009 §6.2 lists "first config sync after sign-in" as its own
        // geofence re-registration trigger, in the same bucket as "resume from pause". Reusing
        // RESUME here means a future A11 hookup on RESUME covers both triggers for free.
        assertEquals(SettingsChangeActions(rebuildSchedule = true, pauseAction = PauseAction.RESUME), actions)
    }

    @Test
    fun `first-ever settings (previous null, tracking off) pauses, never schedules`() {
        val actions = SettingsChangeDecision.decide(null, DeviceSettingsSnapshot(15, false))

        assertEquals(SettingsChangeActions(rebuildSchedule = false, pauseAction = PauseAction.PAUSE), actions)
    }

    @Test
    fun `interval change while tracking stays on rebuilds the schedule, no pause action`() {
        val actions = SettingsChangeDecision.decide(
            DeviceSettingsSnapshot(15, true),
            DeviceSettingsSnapshot(30, true),
        )

        assertEquals(SettingsChangeActions(rebuildSchedule = true, pauseAction = PauseAction.NONE), actions)
    }

    @Test
    fun `unchanged settings do nothing`() {
        val actions = SettingsChangeDecision.decide(
            DeviceSettingsSnapshot(15, true),
            DeviceSettingsSnapshot(15, true),
        )

        assertEquals(SettingsChangeActions(rebuildSchedule = false, pauseAction = PauseAction.NONE), actions)
    }

    @Test
    fun `tracking turning off pauses and does not rebuild, regardless of interval`() {
        val actions = SettingsChangeDecision.decide(
            DeviceSettingsSnapshot(15, true),
            DeviceSettingsSnapshot(30, false),
        )

        assertEquals(SettingsChangeActions(rebuildSchedule = false, pauseAction = PauseAction.PAUSE), actions)
    }

    @Test
    fun `tracking turning back on resumes and rebuilds even if the interval is unchanged`() {
        val actions = SettingsChangeDecision.decide(
            DeviceSettingsSnapshot(15, false),
            DeviceSettingsSnapshot(15, true),
        )

        assertEquals(SettingsChangeActions(rebuildSchedule = true, pauseAction = PauseAction.RESUME), actions)
    }

    @Test
    fun `staying paused across two applications is a no-op`() {
        val actions = SettingsChangeDecision.decide(
            DeviceSettingsSnapshot(15, false),
            DeviceSettingsSnapshot(15, false),
        )

        assertEquals(SettingsChangeActions(rebuildSchedule = false, pauseAction = PauseAction.NONE), actions)
    }

    @Test
    fun `staying paused with a changed interval still does not schedule anything, and does not re-pause`() {
        val actions = SettingsChangeDecision.decide(
            DeviceSettingsSnapshot(15, false),
            DeviceSettingsSnapshot(60, false),
        )

        // trackingEnabled didn't change (still false) - §3.5 only calls for re-applying §4 "if
        // trackingEnabled changed"; the interval alone is irrelevant while nothing is scheduled.
        assertEquals(SettingsChangeActions(rebuildSchedule = false, pauseAction = PauseAction.NONE), actions)
    }
}
