package com.findly.android.device

import android.content.Context

/** Real, thin Android-framework [DeviceIdStore] — untested, like the backend's `src/adapters`
 * (backend/README.md's hexagonal split). Not sensitive (a per-uid UUID, not a credential) — see
 * `res/xml/backup_rules.xml`. */
class SharedPreferencesDeviceIdStore(context: Context) : DeviceIdStore {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun get(uid: String): String? = prefs.getString(keyFor(uid), null)

    override fun put(uid: String, deviceId: String) {
        prefs.edit().putString(keyFor(uid), deviceId).apply()
    }

    override fun clear(uid: String) {
        prefs.edit().remove(keyFor(uid)).apply()
    }

    private fun keyFor(uid: String) = "device_id_$uid"

    private companion object {
        const val PREFS_NAME = "findly_device_ids"
    }
}
