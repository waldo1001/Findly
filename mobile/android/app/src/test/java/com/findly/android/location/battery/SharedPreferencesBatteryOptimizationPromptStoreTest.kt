package com.findly.android.location.battery

import com.findly.android.fakes.FakeSharedPreferences
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [SharedPreferencesBatteryOptimizationPromptStore] against the real class, backed by
 * [FakeSharedPreferences] — same "simulate a cold launch with two store instances over the same
 * backing map" idiom as `SharedPreferencesPermissionDisclosureStoreTest` (this module has no
 * Robolectric/androidTest source set to exercise the real `SharedPreferences` implementation).
 */
class SharedPreferencesBatteryOptimizationPromptStoreTest {

    @Test
    fun `not answered initially`() {
        val store = SharedPreferencesBatteryOptimizationPromptStore(FakeSharedPreferences())
        assertFalse(store.hasAnswered())
    }

    @Test
    fun `recordAnswered survives a simulated cold launch`() {
        val prefs = FakeSharedPreferences()
        SharedPreferencesBatteryOptimizationPromptStore(prefs).recordAnswered()

        val reopened = SharedPreferencesBatteryOptimizationPromptStore(prefs)
        assertTrue(reopened.hasAnswered())
    }
}
