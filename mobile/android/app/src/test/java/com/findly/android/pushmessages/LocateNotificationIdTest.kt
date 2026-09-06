package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Test

/** specs/009-device-runtime.md §5.1 (amended 2026-09-06, A39's final round, finding 1): the
 * `findly_locate` notification id must be scoped **per request**, not global — two
 * `LOCATE_REQUEST`s in flight at once (two family members locating the same device inside the
 * ~45-60s window, or an overlapping locate and presence-reuse capture) used to land on the same
 * global id, so whichever finished first silently removed the other's still-active notification.
 * [LocateNotificationId] is the pure, testable derivation shared by [LocateNotifier]'s `post`,
 * `cancel`, and its two `startForeground`/`getForegroundInfo` callers so all of them key off the
 * same value for a given request. */
class LocateNotificationIdTest {

    @Test
    fun `the same requestId always derives the same notification id`() {
        val first = LocateNotificationId.forRequestId("lr_abc123")
        val second = LocateNotificationId.forRequestId("lr_abc123")
        assertEquals(first, second)
    }

    @Test
    fun `different requestIds do not collide in the common case`() {
        val a = LocateNotificationId.forRequestId("lr_abc123")
        val b = LocateNotificationId.forRequestId("lr_xyz789")
        assertNotEquals(a, b)
    }

    @Test
    fun `the derived id never equals the presence service's notification id`() {
        // LocationForegroundService.NOTIFICATION_ID = 1001 (queue/worker/LocationForegroundService.kt) —
        // a colliding locate id would let a locate post/cancel interfere with the presence service's
        // own foreground notification.
        val presenceServiceNotificationId = 1001
        repeat(50) { i ->
            assertNotSame(presenceServiceNotificationId, LocateNotificationId.forRequestId("lr_$i"))
        }
    }

    @Test
    fun `the derived id is always non-negative`() {
        // requestId is an opaque server-issued string (001 §5.1); String#hashCode can be negative,
        // and a negative notification id is invalid for NotificationManager.
        repeat(50) { i ->
            assert(LocateNotificationId.forRequestId("lr_$i") >= 0) {
                "expected a non-negative notification id for lr_$i"
            }
        }
    }
}
