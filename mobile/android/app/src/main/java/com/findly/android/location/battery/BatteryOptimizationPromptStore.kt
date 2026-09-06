package com.findly.android.location.battery

import android.content.Context
import android.content.SharedPreferences

/**
 * Whether the once-per-install battery-optimisation exemption flow (specs/009-device-runtime.md
 * §3.2) has already been answered — accepted or declined, both count, matching
 * [com.findly.android.location.PermissionDisclosureStore]'s "declining is answering too" rule.
 * Pure Kotlin interface (no `android.*`) so [BatteryOptimizationPromptPolicy] callers are
 * unit-testable without an emulator; [SharedPreferencesBatteryOptimizationPromptStore] is the real
 * implementation.
 */
interface BatteryOptimizationPromptStore {
    fun hasAnswered(): Boolean
    fun recordAnswered()
}

/** Test/default in-memory implementation. */
class InMemoryBatteryOptimizationPromptStore(initial: Boolean = false) : BatteryOptimizationPromptStore {
    private var answered = initial

    override fun hasAnswered(): Boolean = answered
    override fun recordAnswered() {
        answered = true
    }
}

/**
 * The real, `SharedPreferences`-backed implementation. Plain preferences, not encrypted storage:
 * this is a single boolean about whether an OS dialog has already been shown, carrying no
 * location data and no identifier.
 */
class SharedPreferencesBatteryOptimizationPromptStore(
    private val prefs: SharedPreferences,
) : BatteryOptimizationPromptStore {

    constructor(context: Context) : this(
        context.getSharedPreferences("findly.battery_optimization_prompt", Context.MODE_PRIVATE),
    )

    override fun hasAnswered(): Boolean = prefs.getBoolean(KEY_ANSWERED, false)

    override fun recordAnswered() {
        prefs.edit().putBoolean(KEY_ANSWERED, true).apply()
    }

    private companion object {
        const val KEY_ANSWERED = "answered"
    }
}
