package com.findly.android.location.battery

/**
 * specs/009-device-runtime.md §3.2 "Battery-optimisation exemption" (amended 2026-09-06): "Once
 * presence is required... the client MUST, once per install, explain and offer the
 * `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt... the app records the answer, never
 * re-prompts automatically." §7 additionally forbids staging it "before or in the same session as
 * the OS location prompt" — [backgroundPermissionGrantedThisSession] is that guard: true only for
 * the remainder of the process lifetime in which the user just answered the
 * `ACCESS_BACKGROUND_LOCATION` dialog, so this offers on the *next* app open at the earliest, not
 * a bundled follow-up dialog.
 *
 * [presenceRequired] is deliberately not re-derived here — the caller already knows it from
 * [com.findly.android.queue.worker.EffectiveSyncStrategySelector] (interval ≤ 30 **and**
 * background permission granted), and re-deriving the same rule twice is exactly the kind of
 * drift `ServiceRestartDecision`'s doc warns about.
 */
object BatteryOptimizationPromptPolicy {
    fun shouldOffer(
        presenceRequired: Boolean,
        alreadyAnswered: Boolean,
        backgroundPermissionGrantedThisSession: Boolean,
    ): Boolean = presenceRequired && !alreadyAnswered && !backgroundPermissionGrantedThisSession
}
