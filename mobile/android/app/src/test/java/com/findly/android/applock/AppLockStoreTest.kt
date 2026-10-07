package com.findly.android.applock

import com.findly.android.fakes.FakeSharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** specs/010 section 1.4: the setting (off by default) and the background timestamp are local,
 * persisted, and cleared by the end-of-session wipe. */
class AppLockStoreTest {

    @Test
    fun `off by default with no background timestamp`() {
        val store = AppLockStore(InMemoryAppLockPersistence())
        assertFalse(store.enabled.value)
        assertNull(store.backgroundedAt())
    }

    @Test
    fun `setEnabled updates the observable value`() {
        val store = AppLockStore(InMemoryAppLockPersistence())
        store.setEnabled(true)
        assertTrue(store.enabled.value)
        store.setEnabled(false)
        assertFalse(store.enabled.value)
    }

    @Test
    fun `setting and timestamp survive a simulated process death`() {
        val prefs = FakeSharedPreferences()
        val first = AppLockStore(SharedPreferencesAppLockPersistence(prefs))
        first.setEnabled(true)
        first.recordBackgrounded(42L)

        val second = AppLockStore(SharedPreferencesAppLockPersistence(prefs))
        assertTrue(second.enabled.value)
        assertEquals(42L, second.backgroundedAt())
    }

    @Test
    fun `clearBackgrounded removes only the timestamp`() {
        val store = AppLockStore(InMemoryAppLockPersistence())
        store.setEnabled(true)
        store.recordBackgrounded(7L)
        store.clearBackgrounded()
        assertNull(store.backgroundedAt())
        assertTrue(store.enabled.value)
    }

    @Test
    fun `clear wipes setting and timestamp from memory and storage`() {
        val prefs = FakeSharedPreferences()
        val store = AppLockStore(SharedPreferencesAppLockPersistence(prefs))
        store.setEnabled(true)
        store.recordBackgrounded(7L)

        store.clear()

        assertFalse(store.enabled.value)
        assertNull(store.backgroundedAt())
        val reopened = AppLockStore(SharedPreferencesAppLockPersistence(prefs))
        assertFalse(reopened.enabled.value)
        assertNull(reopened.backgroundedAt())
    }
}
