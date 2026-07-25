package com.findly.android.device

/**
 * Persists a per-uid `deviceId` (specs/003-android-client.md §8). Real implementation:
 * [SharedPreferencesDeviceIdStore] (Android). Test fake: `InMemoryDeviceIdStore`
 * (`app/src/test/.../fakes/`, mirrors the backend's `test/fakes/` convention).
 */
interface DeviceIdStore {
    fun get(uid: String): String?
    fun put(uid: String, deviceId: String)

    /** Removes the persisted `deviceId` for [uid] — used only by a full local-state wipe after
     * account deletion (specs/008-privacy-endpoints.md §4.4; specs/003-android-client.md §12.4). */
    fun clear(uid: String)
}
