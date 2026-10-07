package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Test

/** A61 — specs/011 §4.4 / 009 §5.6: `STALE_NUDGE` received in the foreground is dropped, and the
 * `findly_sharing_status` channel has its contracted id/name/importance. */
class StaleNudgeTest {

    @Test
    fun `STALE_NUDGE parses to its own type`() {
        assertEquals(PushMessageType.StaleNudge, PushMessageType.from(mapOf("type" to "STALE_NUDGE")))
    }

    @Test
    fun `STALE_NUDGE takes the drop lane - nothing runs while foregrounded`() {
        assertEquals(PushMessageLane.Drop, PushMessageLanePolicy.decide(PushMessageType.StaleNudge))
    }

    @Test
    fun `unknown types are still ignored via the dispatcher lane`() {
        assertEquals(
            PushMessageLane.Dispatcher,
            PushMessageLanePolicy.decide(PushMessageType.from(mapOf("type" to "SOMETHING_NEW"))),
        )
    }

    @Test
    fun `sharing status channel contract`() {
        assertEquals("findly_sharing_status", SharingStatusChannel.ID)
        assertEquals("Sharing reminders", SharingStatusChannel.NAME)
        assertEquals(3, SharingStatusChannel.IMPORTANCE) // NotificationManager.IMPORTANCE_DEFAULT
    }
}
