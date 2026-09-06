package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Test

/** 001-api-contract.md §8.1's normative title template, rendered on-device from
 * `data.requestedByName` on Android (the FCM message itself is data-only, specs/009 §5.1). */
class LocateNotificationTitleTest {

    @Test
    fun `renders the exact normative template`() {
        assertEquals("Eric is locating you", LocateNotificationTitle.forRequester("Eric"))
    }

    @Test
    fun `works for any display name without extra formatting`() {
        assertEquals("Noor is locating you", LocateNotificationTitle.forRequester("Noor"))
    }
}
