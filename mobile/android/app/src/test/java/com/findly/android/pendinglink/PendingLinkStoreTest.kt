package com.findly.android.pendinglink

import com.findly.android.fakes.FakeSharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** specs/010 §1.3 "Persistence": one slot, memory + app-private local storage, survives the OS
 * killing the app; a newer link replaces an older one; cleared on demand. */
class PendingLinkStoreTest {

    private val a = PendingLink(PendingLinkKind.FamilyInvite, "7F3K9QRZ", receivedAt = 10L)
    private val b = PendingLink(PendingLinkKind.GroupJoin, "AB12CD34", receivedAt = 20L)

    @Test
    fun `starts empty`() {
        assertNull(PendingLinkStore(InMemoryPendingLinkPersistence()).current.value)
    }

    @Test
    fun `save then read back`() {
        val store = PendingLinkStore(InMemoryPendingLinkPersistence())
        store.save(a)
        assertEquals(a, store.current.value)
    }

    @Test
    fun `one slot only - a newer link replaces an older one`() {
        val store = PendingLinkStore(InMemoryPendingLinkPersistence())
        store.save(a)
        store.save(b)
        assertEquals(b, store.current.value)
    }

    @Test
    fun `clear empties memory and storage`() {
        val persistence = InMemoryPendingLinkPersistence()
        val store = PendingLinkStore(persistence)
        store.save(a)
        store.clear()
        assertNull(store.current.value)
        assertNull(persistence.read())
    }

    @Test
    fun `survives simulated process death - a fresh store over the same persistence sees the link`() {
        val prefs = FakeSharedPreferences()
        PendingLinkStore(SharedPreferencesPendingLinkPersistence(prefs)).save(a)

        val afterProcessDeath = PendingLinkStore(SharedPreferencesPendingLinkPersistence(prefs))

        assertEquals(a, afterProcessDeath.current.value)
    }

    @Test
    fun `a cleared slot stays cleared after simulated process death`() {
        val prefs = FakeSharedPreferences()
        val store = PendingLinkStore(SharedPreferencesPendingLinkPersistence(prefs))
        store.save(a)
        store.clear()

        assertNull(PendingLinkStore(SharedPreferencesPendingLinkPersistence(prefs)).current.value)
    }

    @Test
    fun `the preferences file is findly_pending_link`() {
        assertEquals("findly_pending_link", SharedPreferencesPendingLinkPersistence.FILE_NAME)
    }

    @Test
    fun `malformed stored data reads as an empty slot, never a crash`() {
        val prefs = FakeSharedPreferences()
        prefs.edit().putString("kind", "familyInvite").putString("code", "not-a-code").putLong("receivedAt", 5L).apply()
        assertNull(SharedPreferencesPendingLinkPersistence(prefs).read())

        val prefs2 = FakeSharedPreferences()
        prefs2.edit().putString("kind", "mystery").putString("code", "7F3K9QRZ").putLong("receivedAt", 5L).apply()
        assertNull(SharedPreferencesPendingLinkPersistence(prefs2).read())

        assertNull(SharedPreferencesPendingLinkPersistence(FakeSharedPreferences()).read())
    }
}
