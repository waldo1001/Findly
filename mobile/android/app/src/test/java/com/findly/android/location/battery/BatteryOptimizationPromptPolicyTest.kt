package com.findly.android.location.battery

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * specs/009-device-runtime.md §3.2 "Battery-optimisation exemption" (amended 2026-09-06):
 * "Once presence is required... the client MUST, once per install, explain and offer the
 * `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt... the app records the answer, never
 * re-prompts automatically." §7: "stages the §3.2 battery-optimisation prompt after background
 * permission is granted, never before or in the same session as the OS location prompt."
 *
 * [presenceRequired] is the caller's own `EffectiveSyncStrategySelector.strategyFor(interval,
 * granted) is SyncStrategy.ForegroundService` check (interval ≤ 30 **and** background permission
 * already granted) — this policy does not re-derive it, to avoid a second copy of that rule.
 */
class BatteryOptimizationPromptPolicyTest {

    @Test
    fun `offers the prompt when presence is required, unanswered, and background permission was not just granted this session`() {
        assertTrue(
            BatteryOptimizationPromptPolicy.shouldOffer(
                presenceRequired = true,
                alreadyAnswered = false,
                backgroundPermissionGrantedThisSession = false,
            ),
        )
    }

    @Test
    fun `never offers when presence is not required`() {
        assertFalse(
            BatteryOptimizationPromptPolicy.shouldOffer(
                presenceRequired = false,
                alreadyAnswered = false,
                backgroundPermissionGrantedThisSession = false,
            ),
        )
    }

    @Test
    fun `never offers once already answered`() {
        assertFalse(
            BatteryOptimizationPromptPolicy.shouldOffer(
                presenceRequired = true,
                alreadyAnswered = true,
                backgroundPermissionGrantedThisSession = false,
            ),
        )
    }

    @Test
    fun `never offers in the same session the background permission was granted (009 section7 - not bundled with the location grant)`() {
        assertFalse(
            BatteryOptimizationPromptPolicy.shouldOffer(
                presenceRequired = true,
                alreadyAnswered = false,
                backgroundPermissionGrantedThisSession = true,
            ),
        )
    }

    @Test
    fun `offers on a later session once the same-session flag has cleared`() {
        // Simulates: user granted background permission last session (battery prompt withheld
        // that time), then reopened the app - a fresh process means a fresh
        // backgroundPermissionGrantedThisSession = false.
        assertTrue(
            BatteryOptimizationPromptPolicy.shouldOffer(
                presenceRequired = true,
                alreadyAnswered = false,
                backgroundPermissionGrantedThisSession = false,
            ),
        )
    }
}
