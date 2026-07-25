package com.findly.android.fakes

import com.findly.android.device.DeviceIdStore

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). The real
 * implementation is `SharedPreferencesDeviceIdStore` (specs/003-android-client.md §8). */
class InMemoryDeviceIdStore : DeviceIdStore {
    private val map = mutableMapOf<String, String>()

    override fun get(uid: String): String? = map[uid]

    override fun put(uid: String, deviceId: String) {
        map[uid] = deviceId
    }

    override fun clear(uid: String) {
        map.remove(uid)
    }
}
