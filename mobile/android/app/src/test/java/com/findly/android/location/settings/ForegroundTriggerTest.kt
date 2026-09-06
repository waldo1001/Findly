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
    fun `runOnce still runs even when poll throws nothing to report`() = runTest {
        // poll() itself never throws in the real DeviceSettingsCoordinator/SettingsPoller path
        // (specs/009 §4/§9 route every failure to a PollOutcome), but this pins that the trigger
        // does not accidentally skip runOnce - e.g. via an early return - for any poll outcome.
        var runOnceCalled = false
        val trigger = ForegroundTrigger(
            poll = { /* no-op poll outcome */ },
            runOnce = { runOnceCalled = true },
        )

        trigger.run()

        assertEquals(true, runOnceCalled)
    }
}
