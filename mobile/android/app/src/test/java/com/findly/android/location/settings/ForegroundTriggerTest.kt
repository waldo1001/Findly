package com.findly.android.location.settings

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** specs/009-device-runtime.md §1.4 / §12: "every foreground runs one full `runOnce` cycle" — a
 * checklist line the A40 commit (`ed3dd57`) shipped with zero test coverage (code-review finding
 * 3, post-A40 review) even though every other §12 line in scope was covered. This pins the
 * sequence [ForegroundTrigger] extracts out of `AppContainer.onAppForeground`. */
class ForegroundTriggerTest {

    @Test
    fun `runs poll then runOnce, in order, exactly once`() = runTest {
        val calls = mutableListOf<String>()
        val trigger = ForegroundTrigger(
            poll = { calls += "poll" },
            runOnce = { calls += "runOnce" },
        )

        trigger.run()

        assertEquals(listOf("poll", "runOnce"), calls)
    }

    @Test
    fun `runOnce still runs when poll throws`() = runTest {
        // Round-3 post-A40 review (finding 5): the previous version of this test was named for
        // poll() throwing but exercised a no-op poll(), making it a near-duplicate of the test
        // above under a misleading name. poll() itself never throws in the real
        // DeviceSettingsCoordinator/SettingsPoller path (specs/009 §4/§9 route every failure to a
        // PollOutcome) - but a foreground runOnce cycle is more valuable to a person than the
        // settings poll that precedes it (specs/009 §1.4), so a defensive poll failure must not
        // cost them the whole foreground sync. This pins that [ForegroundTrigger.run] swallows a
        // throwing poll() (anything but CancellationException) rather than propagating it and
        // skipping runOnce.
        var runOnceCalled = false
        val trigger = ForegroundTrigger(
            poll = { throw IllegalStateException("boom") },
            runOnce = { runOnceCalled = true },
        )

        trigger.run()

        assertEquals(true, runOnceCalled)
    }
}
