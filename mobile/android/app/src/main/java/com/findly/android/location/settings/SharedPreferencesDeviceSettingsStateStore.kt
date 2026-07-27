package com.findly.android.location.settings

import android.content.Context
import com.findly.android.network.DeviceSettingsSnapshot

/** Real, thin Android-framework [DeviceSettingsStateStore] — untested, like
 * `SharedPreferencesDeviceIdStore` (specs/003-android-client.md §3). Not sensitive (an interval
 * + a boolean, not a credential). */
class SharedPreferencesDeviceSettingsStateStore(context: Context) : DeviceSettingsStateStore {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override suspend fun current(): DeviceSettingsSnapshot? {
        if (!prefs.contains(KEY_INTERVAL)) return null
        val interval = prefs.getInt(KEY_INTERVAL, 0)
        val trackingEnabled = prefs.getBoolean(KEY_TRACKING_ENABLED, true)
        return DeviceSettingsSnapshot(interval, trackingEnabled)
    }

    override suspend fun update(settings: DeviceSettingsSnapshot) {
        prefs.edit()
            .putInt(KEY_INTERVAL, settings.syncIntervalMinutes)
            .putBoolean(KEY_TRACKING_ENABLED, settings.trackingEnabled)
            .apply()
    }

    private companion object {
        const val PREFS_NAME = "findly_device_settings"
        const val KEY_INTERVAL = "sync_interval_minutes"
        const val KEY_TRACKING_ENABLED = "tracking_enabled"
    }
}
