package com.findly.android.ui.designsystem.components

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [FindlyDropdownOption.closedFieldText] is the pure formatting rule behind
 * specs/010-app-shell-and-screen-ux.md §4.2's "the closed field shows the group name after the
 * value (e.g. `15 min · Live`)" — extracted as a plain function (no Compose types in its
 * signature) so the exact format is unit-testable without a Compose test harness (this repo has
 * none, backlog row A38).
 */
class FindlyDropdownFieldTest {

    @Test
    fun `an option with a group label appends it after the label, separated by a middle dot`() {
        val option = FindlyDropdownOption(value = 15, label = "15 min", groupLabel = "Live")
        assertEquals("15 min · Live", option.closedFieldText())
    }

    @Test
    fun `an option with no group label is shown as-is`() {
        val option = FindlyDropdownOption(value = 15, label = "15 min")
        assertEquals("15 min", option.closedFieldText())
    }
}
