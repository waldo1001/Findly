package com.findly.android.ui.designsystem.components

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FindlyNavDrawerGesturesTest {
    @Test
    fun closedDrawerDisablesGestures() {
        assertFalse(FindlyNavDrawerGestures.enabled(isOpen = false))
    }

    @Test
    fun openDrawerEnablesGestures() {
        assertTrue(FindlyNavDrawerGestures.enabled(isOpen = true))
    }
}
