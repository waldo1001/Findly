package com.findly.android.ui.devices

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A61 — pure policies for specs/011 §1.1 (Remove action visibility), §2 / §1.1 (Inactive chip),
 * §4.4 (nudge toggle visibility) and the 010 §4.2 bullet 5 "Last seen" line. */
class DeviceLifecyclePolicyTest {

    @Test
    fun `remove action visibility matrix - parent or owner, never this device`() {
        // (isParent, isOwner, isThisDevice) -> canRemove
        val table = listOf(
            Triple(true, false, false) to true, // parent, someone else's device
            Triple(true, true, false) to true, // parent, own other device
            Triple(false, true, false) to true, // member, own other device
            Triple(false, false, false) to false, // member, someone else's device
            Triple(true, false, true) to false, // never on this device
            Triple(true, true, true) to false,
            Triple(false, true, true) to false,
            Triple(false, false, true) to false,
        )
        for ((input, expected) in table) {
            val (parent, owner, thisDevice) = input
            assertEquals(
                "parent=$parent owner=$owner this=$thisDevice",
                expected,
                DeviceLifecyclePolicy.canRemove(isParent = parent, isOwner = owner, isThisDevice = thisDevice),
            )
        }
    }

    @Test
    fun `nudge toggle is shown only on devices the caller owns, in every role`() {
        assertTrue(DeviceLifecyclePolicy.showsNudgeToggle(isOwner = true))
        assertFalse(DeviceLifecyclePolicy.showsNudgeToggle(isOwner = false))
    }

    @Test
    fun `dormant shows Inactive in place of Active or Paused`() {
        assertEquals("Inactive", DeviceLifecyclePolicy.statusLabel(trackingEnabled = true, isDormant = true))
        assertEquals("Inactive", DeviceLifecyclePolicy.statusLabel(trackingEnabled = false, isDormant = true))
        assertEquals("Active", DeviceLifecyclePolicy.statusLabel(trackingEnabled = true, isDormant = false))
        assertEquals("Paused", DeviceLifecyclePolicy.statusLabel(trackingEnabled = false, isDormant = false))
    }

    @Test
    fun `last seen line uses the relative time formatter and is absent without lastSeenAt`() {
        assertEquals(
            "Last seen 5 min ago",
            DeviceLifecyclePolicy.lastSeenLine("2026-07-19T09:00:00Z", nowIso = "2026-07-19T09:05:00Z"),
        )
        assertNull(DeviceLifecyclePolicy.lastSeenLine(null, nowIso = "2026-07-19T09:05:00Z"))
    }

    @Test
    fun `remove dialog copy is the normative 011 text`() {
        assertEquals("Remove \"Pixel 9\"?", DeviceLifecyclePolicy.removeDialogTitle("Pixel 9"))
        assertEquals(
            "Its last known location is deleted. Location history stays until it expires. " +
                "If this phone still has Findly, it will reappear the next time Findly opens on it.",
            DeviceLifecyclePolicy.REMOVE_DIALOG_BODY,
        )
        assertEquals(
            "Only a parent can remove another member's device.",
            DeviceLifecyclePolicy.REMOVE_FORBIDDEN_MESSAGE,
        )
    }
}
