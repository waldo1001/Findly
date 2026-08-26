package com.findly.android.ui.map

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §3.1 (normative — the handoff's minimized-detent content
 * list includes "avatar stack" on equal footing with grabber/title/summary/Locate-now,
 * HANDOFF.md:151; 010 deliberately kept it while dropping the handoff's "Drag up for details"
 * hint, a curated inclusion, not an oversight). [RosterAvatarStackPlan] is the pure decision of
 * which initials to show and how many members overflow — [com.findly.android.ui.map.MapScreen]'s
 * `RosterHeader` and [com.findly.android.ui.groups.GroupMapScreen]'s `GroupRosterHeader` render
 * whatever this returns.
 */
class RosterAvatarStackPlanTest {

    @Test
    fun `empty roster yields no visible avatars and no overflow`() {
        val plan = RosterAvatarStackPlan.compute(emptyList())
        assertEquals(emptyList<String>(), plan.visibleInitials)
        assertEquals(0, plan.overflowCount)
    }

    @Test
    fun `fewer members than the max show all of them with no overflow`() {
        val plan = RosterAvatarStackPlan.compute(listOf("Eric", "Noor"), maxVisible = 4)
        assertEquals(listOf("ER", "NO"), plan.visibleInitials)
        assertEquals(0, plan.overflowCount)
    }

    @Test
    fun `exactly the max shows all of them with no overflow`() {
        val plan = RosterAvatarStackPlan.compute(listOf("Aaa", "Bbb", "Ccc", "Ddd"), maxVisible = 4)
        assertEquals(listOf("AA", "BB", "CC", "DD"), plan.visibleInitials)
        assertEquals(0, plan.overflowCount)
    }

    @Test
    fun `more members than the max caps visible avatars and counts the overflow`() {
        val plan = RosterAvatarStackPlan.compute(
            listOf("Eric", "Noor", "Alex", "Sam", "Kai", "Zoe"),
            maxVisible = 4,
        )
        assertEquals(listOf("ER", "NO", "AL", "SA"), plan.visibleInitials)
        assertEquals(2, plan.overflowCount)
    }

    @Test
    fun `a blank display name renders a neutral question mark, never a crash`() {
        val plan = RosterAvatarStackPlan.compute(listOf("   "))
        assertEquals(listOf("?"), plan.visibleInitials)
        assertEquals(0, plan.overflowCount)
    }

    @Test
    fun `initials are the first two characters uppercased, matching the marker convention`() {
        assertEquals("ER", RosterAvatarStackPlan.initialsFor("eric"))
        assertEquals("N", RosterAvatarStackPlan.initialsFor("n"))
        assertEquals("?", RosterAvatarStackPlan.initialsFor(""))
    }

    @Test
    fun `default maxVisible is 4`() {
        assertEquals(4, RosterAvatarStackPlan.MAX_VISIBLE)
    }
}
