package com.findly.android.location.battery

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * specs/010-app-shell-and-screen-ux.md §4.2: "The card also gains a 'Battery settings' action on
 * Android (009 §3.2) that opens the battery-optimisation prompt or, once answered, the system
 * battery page."
 */
class BatterySettingsActionPolicyTest {

    @Test
    fun `not yet answered - opens the prompt`() {
        assertEquals(
            BatterySettingsAction.OfferPrompt,
            BatterySettingsActionPolicy.actionFor(hasAnswered = false),
        )
    }

    @Test
    fun `already answered (accepted or declined) - opens the system battery page`() {
        assertEquals(
            BatterySettingsAction.OpenSystemBatterySettings,
            BatterySettingsActionPolicy.actionFor(hasAnswered = true),
        )
    }
}
