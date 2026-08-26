package com.findly.android.ui.designsystem.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** [FindlyNavDrawerItems] is plain Kotlin (no Compose import) — the 010-app-shell-and-screen-ux.md
 * §1.2 drawer item list/order and "Invite someone" parent-gating, unit-tested without Robolectric
 * (§10's "Drawer: parent-gating of 'Invite someone'; item list/order"). */
class FindlyNavDrawerItemsTest {

    @Test
    fun `a parent sees every item, in the 010 §1_2 normative order, including Invite someone`() {
        val items = FindlyNavDrawerItems.build(isParent = true)

        assertEquals(
            listOf(
                FindlyNavDrawerDestination.FamilyMap,
                FindlyNavDrawerDestination.History,
                FindlyNavDrawerDestination.Geofences,
                FindlyNavDrawerDestination.Devices,
                FindlyNavDrawerDestination.Family,
                FindlyNavDrawerDestination.InviteSomeone,
                FindlyNavDrawerDestination.Groups,
                FindlyNavDrawerDestination.PrivacyAndData,
            ),
            items.map { it.destination },
        )
    }

    @Test
    fun `a non-parent never sees Invite someone, and every other item keeps its order`() {
        val items = FindlyNavDrawerItems.build(isParent = false)

        assertFalse(items.any { it.destination == FindlyNavDrawerDestination.InviteSomeone })
        assertEquals(
            listOf(
                FindlyNavDrawerDestination.FamilyMap,
                FindlyNavDrawerDestination.History,
                FindlyNavDrawerDestination.Geofences,
                FindlyNavDrawerDestination.Devices,
                FindlyNavDrawerDestination.Family,
                FindlyNavDrawerDestination.Groups,
                FindlyNavDrawerDestination.PrivacyAndData,
            ),
            items.map { it.destination },
        )
    }

    @Test
    fun `the Family map item is marked selected by default (the root screen)`() {
        val items = FindlyNavDrawerItems.build(isParent = true)

        assertTrue(items.single { it.destination == FindlyNavDrawerDestination.FamilyMap }.selected)
        assertTrue(items.filterNot { it.destination == FindlyNavDrawerDestination.FamilyMap }.none { it.selected })
    }

    @Test
    fun `an explicit selected destination is reflected instead`() {
        val items = FindlyNavDrawerItems.build(isParent = true, selected = FindlyNavDrawerDestination.History)

        assertTrue(items.single { it.destination == FindlyNavDrawerDestination.History }.selected)
        assertFalse(items.single { it.destination == FindlyNavDrawerDestination.FamilyMap }.selected)
    }

    @Test
    fun `every item carries a non-blank label`() {
        FindlyNavDrawerItems.build(isParent = true).forEach { item ->
            assertTrue("label for ${item.destination} must not be blank", item.label.isNotBlank())
        }
    }
}
