package com.findly.android.location.battery

/**
 * specs/010-app-shell-and-screen-ux.md §4.2: "The card also gains a 'Battery settings' action on
 * Android (009 §3.2) that opens the battery-optimisation prompt or, once answered, the system
 * battery page." The action is deliberately keyed only on whether the flow has already been
 * answered — not on [BatteryOptimizationPromptPolicy.shouldOffer]'s full condition — because a
 * user tapping this button is an explicit request, not the once-per-install automatic offer: it
 * MUST still work even when presence is not currently required (e.g. the interval was raised to
 * battery-saver after the exemption was granted, and the user wants to check/revoke it), and it
 * MUST NOT re-explain with the rationale screen on every tap once the flow has already run once.
 */
sealed class BatterySettingsAction {
    /** Nothing answered yet — walk the user through the rationale then the OS prompt, exactly
     * like the once-per-install automatic offer. */
    data object OfferPrompt : BatterySettingsAction()

    /** Already answered (accepted or declined) — Android will not show the OS dialog again for
     * an app that already has an answer, so the only useful destination is the system's own
     * per-app battery settings page. */
    data object OpenSystemBatterySettings : BatterySettingsAction()
}

object BatterySettingsActionPolicy {
    fun actionFor(hasAnswered: Boolean): BatterySettingsAction =
        if (hasAnswered) BatterySettingsAction.OpenSystemBatterySettings else BatterySettingsAction.OfferPrompt
}
