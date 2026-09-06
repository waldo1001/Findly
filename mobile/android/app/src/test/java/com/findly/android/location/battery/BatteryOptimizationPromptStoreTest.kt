package com.findly.android.location.battery

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** [InMemoryBatteryOptimizationPromptStore] against the [BatteryOptimizationPromptStore]
 * contract — specs/009 §3.2: "the app records the answer, never re-prompts automatically." */
class BatteryOptimizationPromptStoreTest {

    @Test
    fun `not answered initially`() {
        val store = InMemoryBatteryOptimizationPromptStore()
        assertFalse(store.hasAnswered())
    }

    @Test
    fun `recordAnswered persists true`() {
        val store = InMemoryBatteryOptimizationPromptStore()
        store.recordAnswered()
        assertTrue(store.hasAnswered())
    }
}
