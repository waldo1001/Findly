package com.findly.android.ui.permissions

import com.findly.android.location.PermissionDisclosureKind

/**
 * specs/009-device-runtime.md §7 — the prominent-disclosure bullet copy, kept free of Compose so
 * the required wording is unit-testable. [PermissionDisclosureScreen] renders it.
 *
 * The three things a disclosure has to answer: what is collected, what it is used for, and who can
 * see it. Written plainly — a family member reads this, not a lawyer.
 */
object PermissionDisclosureCopy {

    fun points(kind: PermissionDisclosureKind): List<String> = when (kind) {
        PermissionDisclosureKind.FOREGROUND -> listOf(
            "Findly collects this device's location so it can appear on your family's map.",
            "Only people in the families and groups you have joined can see it. It is never sold or shared with anyone else.",
            "You can pause sharing at any time in Settings, and delete your history and account from inside the app.",
        )
        PermissionDisclosureKind.BACKGROUND -> listOf(
            "To keep the map up to date, Findly needs to collect your location even when the app is closed or not in use.",
            "This is what lets your family see where you are without you opening the app, and what makes arrival and departure alerts work for places like home or school.",
            "Background updates follow the interval you choose in Settings, and stop entirely when you pause sharing.",
            // 009 §7 "Presence needs background permission": required, verbatim, as its own point.
            "Without 'Allow all the time', your family only sees you while Findly is open, and 'Locate now' cannot reach this phone.",
        )
    }
}
