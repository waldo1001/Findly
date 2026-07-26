package com.findly.android.pushmessages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** 001-api-contract.md §8.2 — the exact, normative title template: no time text (the
 * notification's own timestamp conveys time in the recipient's locale/zone). */
class GeofenceEventNotificationTemplateTest {

    private fun data(
        displayName: String? = "Noor",
        geofenceName: String? = "Home",
        transition: String? = "enter",
    ): Map<String, String> = buildMap {
        displayName?.let { put("displayName", it) }
        geofenceName?.let { put("geofenceName", it) }
        transition?.let { put("transition", it) }
    }

    @Test
    fun `enter renders the arrived-at template`() {
        assertEquals("Noor arrived at Home", GeofenceEventNotificationTemplate.titleFor(data()))
    }

    @Test
    fun `exit renders the left template`() {
        assertEquals(
            "Noor left Home",
            GeofenceEventNotificationTemplate.titleFor(data(transition = "exit")),
        )
    }

    @Test
    fun `missing displayName yields null instead of throwing`() {
        assertNull(GeofenceEventNotificationTemplate.titleFor(data(displayName = null)))
    }

    @Test
    fun `blank displayName yields null instead of throwing`() {
        assertNull(GeofenceEventNotificationTemplate.titleFor(data(displayName = "")))
    }

    @Test
    fun `missing geofenceName yields null instead of throwing`() {
        assertNull(GeofenceEventNotificationTemplate.titleFor(data(geofenceName = null)))
    }

    @Test
    fun `missing transition yields null instead of throwing`() {
        assertNull(GeofenceEventNotificationTemplate.titleFor(data(transition = null)))
    }

    @Test
    fun `unknown transition value yields null instead of throwing`() {
        assertNull(GeofenceEventNotificationTemplate.titleFor(data(transition = "loiter")))
    }

    @Test
    fun `empty payload yields null instead of throwing`() {
        assertNull(GeofenceEventNotificationTemplate.titleFor(emptyMap()))
    }
}
