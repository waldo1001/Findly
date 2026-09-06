package com.findly.android.pushmessages

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/009-device-runtime.md §5.1 diagnostic note: comparing `RemoteMessage.getPriority()` with
 * `getOriginalPriority()` tells the client FCM demoted this app's messages — "the single most
 * useful field diagnostic for this whole batch" — but the comparison itself must stay a pure,
 * testable boolean so the framework glue that logs it (a count only, never payload content) has
 * nothing left to get wrong. */
class PushPriorityDemotionTest {

    @Test
    fun `identical priority and originalPriority is not a demotion`() {
        assertFalse(PushPriorityDemotion.wasDemoted(priority = 1, originalPriority = 1))
    }

    @Test
    fun `a lower delivered priority than originally set is a demotion`() {
        // RemoteMessage.PRIORITY_HIGH = 1, PRIORITY_NORMAL = 2 (Firebase Messaging SDK constants);
        // this class deliberately takes plain ints so it never needs the SDK on the test classpath.
        assertTrue(PushPriorityDemotion.wasDemoted(priority = 2, originalPriority = 1))
    }

    @Test
    fun `both unknown (0) is not a demotion`() {
        assertFalse(PushPriorityDemotion.wasDemoted(priority = 0, originalPriority = 0))
    }
}
