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

    // Nit fix (A39 review): PRIORITY_UNKNOWN (0) on either side means the SDK didn't populate
    // that field - not that FCM downgraded the message - so it must never count as a demotion on
    // its own, even against a genuinely different value on the other side.

    @Test
    fun `an unknown originalPriority is never counted as a demotion, even against a different delivered priority`() {
        assertFalse(PushPriorityDemotion.wasDemoted(priority = 1, originalPriority = 0))
    }

    @Test
    fun `an unknown delivered priority is never counted as a demotion, even against a different original priority`() {
        assertFalse(PushPriorityDemotion.wasDemoted(priority = 0, originalPriority = 1))
    }
}
