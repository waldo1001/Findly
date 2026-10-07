package com.findly.android.ui.devices

import com.findly.android.ui.map.RelativeTimeFormatter

/**
 * Pure rules of the device lifecycle rows on the Devices card (specs/010 §4.2 bullet 5,
 * specs/011 §1.1, §2, §4.4). Kept out of the composables so they are unit-tested.
 */
object DeviceLifecyclePolicy {
    const val REMOVE_DIALOG_BODY =
        "Its last known location is deleted. Location history stays until it expires. " +
            "If this phone still has Findly, it will reappear the next time Findly opens on it."
    const val REMOVE_FORBIDDEN_MESSAGE = "Only a parent can remove another member's device."

    fun removeDialogTitle(deviceName: String): String = "Remove \"$deviceName\"?"

    /** 011 §1.1: parent or owner — never the device this app runs on (it would just re-register). */
    fun canRemove(isParent: Boolean, isOwner: Boolean, isThisDevice: Boolean): Boolean =
        !isThisDevice && (isParent || isOwner)

    /** 011 §4.4: the nudge is the owner's own preference — shown only on owned devices, any role. */
    fun showsNudgeToggle(isOwner: Boolean): Boolean = isOwner

    /** 011 §1.1/§2: a dormant device shows Inactive in place of Active (and Paused). */
    fun statusLabel(trackingEnabled: Boolean, isDormant: Boolean): String = when {
        isDormant -> "Inactive"
        trackingEnabled -> "Active"
        else -> "Paused"
    }

    /** 011 §1.1 / 001 §4.2: omitted (null) when `lastSeenAt` is absent. */
    fun lastSeenLine(lastSeenAt: String?, nowIso: String): String? {
        if (lastSeenAt == null) return null
        val relative = RelativeTimeFormatter.format(lastSeenAt, nowIso)
        return "Last seen ${if (relative == "Just now") "just now" else relative}"
    }
}
