package com.findly.android.device

/**
 * Persists a per-uid `deviceId` (specs/003-android-client.md §8). Real implementation:
 * [SharedPreferencesDeviceIdStore] (Android). Test fake: `InMemoryDeviceIdStore`
 * (`app/src/test/.../fakes/`, mirrors the backend's `test/fakes/` convention).
 */
interface DeviceIdStore {
    fun get(uid: String): String?
    fun put(uid: String, deviceId: String)
}
