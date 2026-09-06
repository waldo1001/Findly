package com.findly.android.location.settings

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §3.2 "Restart and recovery": [BootCompletedReceiver] must react
 * only to `ACTION_BOOT_COMPLETED`/`ACTION_MY_PACKAGE_REPLACED`. Extracted out of the receiver's
 * `onReceive` action check (code-review finding 3, post-A40 review: "an action check is testable
 * logic, not framework glue"). */
class BootCompletedActionGateTest {

    @Test
    fun `boot completed - reapply`() {
        assertTrue(BootCompletedActionGate.shouldReapply("android.intent.action.BOOT_COMPLETED"))
    }

    @Test
    fun `package replaced - reapply`() {
        assertTrue(BootCompletedActionGate.shouldReapply("android.intent.action.MY_PACKAGE_REPLACED"))
    }

    @Test
    fun `unrelated action - ignored`() {
        assertFalse(BootCompletedActionGate.shouldReapply("android.intent.action.SCREEN_ON"))
    }

    @Test
    fun `null action - ignored`() {
        assertFalse(BootCompletedActionGate.shouldReapply(null))
    }
}
