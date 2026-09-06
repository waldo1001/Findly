package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §5.1 "Android execution model" — the three-way choice
 * `onMessageReceived` must make without ever blocking on it (A39). Order matters and is normative:
 * an already-running §3.2 presence service takes priority over starting a second foreground
 * service ("no second service"); failing that, a high-priority message with background location
 * granted gets the short-lived FGS exemption; everything else falls back to expedited WorkManager
 * (demoted priority, or background permission absent). */
class LocateHandoffPolicyTest {

    @Test
    fun `presence already running wins regardless of priority or permission`() {
        assertEquals(
            LocateHandoffDecision.UsePresenceService,
            LocateHandoffPolicy.decide(isHighPriority = true, backgroundLocationGranted = true, presenceServiceRunning = true),
        )
        assertEquals(
            LocateHandoffDecision.UsePresenceService,
            LocateHandoffPolicy.decide(isHighPriority = false, backgroundLocationGranted = false, presenceServiceRunning = true),
        )
    }

    @Test
    fun `high priority plus background permission starts the short-lived foreground service`() {
        assertEquals(
            LocateHandoffDecision.StartForegroundService,
            LocateHandoffPolicy.decide(isHighPriority = true, backgroundLocationGranted = true, presenceServiceRunning = false),
        )
    }

    @Test
    fun `demoted priority falls back to expedited WorkManager even with background permission`() {
        assertEquals(
            LocateHandoffDecision.ExpeditedWorkManager,
            LocateHandoffPolicy.decide(isHighPriority = false, backgroundLocationGranted = true, presenceServiceRunning = false),
        )
    }

    @Test
    fun `missing background permission falls back to expedited WorkManager even at high priority`() {
        assertEquals(
            LocateHandoffDecision.ExpeditedWorkManager,
            LocateHandoffPolicy.decide(isHighPriority = true, backgroundLocationGranted = false, presenceServiceRunning = false),
        )
    }

    @Test
    fun `demoted and no permission also falls back to expedited WorkManager`() {
        assertEquals(
            LocateHandoffDecision.ExpeditedWorkManager,
            LocateHandoffPolicy.decide(isHighPriority = false, backgroundLocationGranted = false, presenceServiceRunning = false),
        )
    }
}
