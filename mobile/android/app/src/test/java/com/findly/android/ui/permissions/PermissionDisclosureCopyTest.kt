package com.findly.android.ui.permissions

import com.findly.android.location.PermissionDisclosureKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** specs/009-device-runtime.md §7 "Presence needs background permission" (A67). */
class PermissionDisclosureCopyTest {

    private val required =
        "Without 'Allow all the time', your family only sees you while Findly is open, and 'Locate now' cannot reach this phone."

    @Test
    fun backgroundDisclosureStatesWhatAllowAllTheTimeEnables() {
        val points = PermissionDisclosureCopy.points(PermissionDisclosureKind.BACKGROUND)
        assertEquals(1, points.count { it == required })
    }

    @Test
    fun requiredSentenceIsTheLastBackgroundPoint() {
        assertEquals(required, PermissionDisclosureCopy.points(PermissionDisclosureKind.BACKGROUND).last())
    }

    @Test
    fun foregroundDisclosureDoesNotCarryTheBackgroundSentence() {
        assertFalse(PermissionDisclosureCopy.points(PermissionDisclosureKind.FOREGROUND).contains(required))
    }
}
