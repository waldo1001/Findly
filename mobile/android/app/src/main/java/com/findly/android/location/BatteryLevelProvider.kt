package com.findly.android.location

/** The current battery level as an integer percentage 0–100 (001-api-contract.md §1.4's
 * `batteryPct`). [AndroidBatteryLevelProvider] is the real, `BatteryManager`-backed implementation. */
fun interface BatteryLevelProvider {
    fun currentBatteryPct(): Int
}
