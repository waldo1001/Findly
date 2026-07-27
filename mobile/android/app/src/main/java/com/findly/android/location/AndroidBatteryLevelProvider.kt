package com.findly.android.location

import android.content.Context
import android.os.BatteryManager

/** Real, `BatteryManager`-backed [BatteryLevelProvider]. Thin Android-framework glue, untested
 * (same bucket as `AndroidDeviceInfoProvider`, specs/003-android-client.md §3). */
class AndroidBatteryLevelProvider(context: Context) : BatteryLevelProvider {
    private val batteryManager = context.applicationContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager

    override fun currentBatteryPct(): Int =
        batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
}
