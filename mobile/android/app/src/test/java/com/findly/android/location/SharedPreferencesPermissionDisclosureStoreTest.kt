package com.findly.android.location

import com.findly.android.fakes.FakeSharedPreferences
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Code-review fix (A25 round 1, Minor 2): every persistence test up to this point ran against
 * [InMemoryPermissionDisclosureStore] only — the "survives a cold launch" claim
 * ([PermissionDisclosureStore]'s own doc, and this task's A25 fix for defect 2) rested entirely on
 * [SharedPreferencesPermissionDisclosureStore], the real implementation, with zero direct coverage.
 *
 * This module has no Robolectric and no `androidTest` source set (`app/build.gradle.kts`), so
 * nothing here can exercise Android's actual `SharedPreferences` implementation or a real `Context`.
 * [com.findly.android.fakes.FakeSharedPreferences] is a from-scratch, in-memory implementation of
 * the (interface-only) `SharedPreferences`/`SharedPreferences.Editor` contract — no Android runtime
 * call involved — which lets these tests exercise the *real* `SharedPreferencesPermissionDisclosureStore`
 * class end to end: its actual key names, its actual `getBoolean`/`putBoolean`/`remove`/`apply`
 * calls. "Cold launch" is simulated the only way a JVM unit test can: two separate store instances
 * constructed over the *same* underlying [FakeSharedPreferences] (a real cold launch reopens the
 * same on-disk file; this reopens the same in-memory one) — a value written by the first instance
 * must be visible from the second, or it was never actually persisted.
 */
class SharedPreferencesPermissionDisclosureStoreTest {

    @Test
    fun `nothing is acknowledged or declined initially`() {
        val store = SharedPreferencesPermissionDisclosureStore(FakeSharedPreferences())

        assertFalse(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.BACKGROUND))
        assertFalse(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `acknowledgement survives a simulated cold launch (a fresh store instance over the same prefs)`() {
        val prefs = FakeSharedPreferences()
        SharedPreferencesPermissionDisclosureStore(prefs).acknowledge(PermissionDisclosureKind.FOREGROUND)

        // A genuinely new instance, exactly what MainActivity.readPermissionState() constructs
        // fresh on every cold launch via AppContainer — not the same object with a still-warm cache.
        val afterColdLaunch = SharedPreferencesPermissionDisclosureStore(prefs)

        assertTrue(afterColdLaunch.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
    }

    @Test
    fun `acknowledging one kind does not acknowledge the other`() {
        val store = SharedPreferencesPermissionDisclosureStore(FakeSharedPreferences())

        store.acknowledge(PermissionDisclosureKind.FOREGROUND)

        assertTrue(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.BACKGROUND))
    }

    // --- A25: the actual bug being fixed was decline not surviving a cold launch — this is the
    // most load-bearing test in this file. ---

    @Test
    fun `decline survives a simulated cold launch (a fresh store instance over the same prefs)`() {
        val prefs = FakeSharedPreferences()
        SharedPreferencesPermissionDisclosureStore(prefs).decline(PermissionDisclosureKind.FOREGROUND)

        val afterColdLaunch = SharedPreferencesPermissionDisclosureStore(prefs)

        assertTrue(
            "the real A25 bug: 'Not now' must be readable by a BRAND NEW store instance, the same " +
                "way readPermissionState() constructs one fresh on every launch — an in-memory-only " +
                "flag would fail exactly this assertion",
            afterColdLaunch.isDeclined(PermissionDisclosureKind.FOREGROUND),
        )
    }

    @Test
    fun `declining one kind does not decline the other`() {
        val store = SharedPreferencesPermissionDisclosureStore(FakeSharedPreferences())

        store.decline(PermissionDisclosureKind.BACKGROUND)

        assertTrue(store.isDeclined(PermissionDisclosureKind.BACKGROUND))
        assertFalse(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
    }

    @Test
    fun `acknowledge and decline are stored independently for the same kind`() {
        // Real key-collision regression guard: acknowledge() and decline() must not accidentally
        // share a preference key for the same kind.
        val store = SharedPreferencesPermissionDisclosureStore(FakeSharedPreferences())

        store.decline(PermissionDisclosureKind.FOREGROUND)

        assertTrue(store.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertFalse(store.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
    }

    @Test
    fun `clearDeclined forgets only that kind's decline, surviving a cold launch too`() {
        val prefs = FakeSharedPreferences()
        val store = SharedPreferencesPermissionDisclosureStore(prefs)
        store.decline(PermissionDisclosureKind.FOREGROUND)
        store.decline(PermissionDisclosureKind.BACKGROUND)

        store.clearDeclined(PermissionDisclosureKind.FOREGROUND)
        val afterColdLaunch = SharedPreferencesPermissionDisclosureStore(prefs)

        assertFalse(afterColdLaunch.isDeclined(PermissionDisclosureKind.FOREGROUND))
        assertTrue(afterColdLaunch.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }

    @Test
    fun `clear forgets every acknowledgement and decline, surviving a cold launch too`() {
        // The account-deletion local wipe path (specs/008 §4.4; A25's DefaultLocalStateWiper fix).
        val prefs = FakeSharedPreferences()
        val store = SharedPreferencesPermissionDisclosureStore(prefs)
        store.acknowledge(PermissionDisclosureKind.FOREGROUND)
        store.decline(PermissionDisclosureKind.BACKGROUND)

        store.clear()
        val afterColdLaunch = SharedPreferencesPermissionDisclosureStore(prefs)

        assertFalse(afterColdLaunch.isAcknowledged(PermissionDisclosureKind.FOREGROUND))
        assertFalse(afterColdLaunch.isDeclined(PermissionDisclosureKind.BACKGROUND))
    }
}
