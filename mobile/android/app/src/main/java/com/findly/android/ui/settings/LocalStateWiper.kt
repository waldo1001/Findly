package com.findly.android.ui.settings

import com.findly.android.device.DeviceIdStore
import com.findly.android.queue.FixQueueStore

/**
 * Wipes every piece of local client state after a successful account deletion
 * (specs/008-privacy-endpoints.md §4.4; specs/003-android-client.md §12.4: "on success wipe ALL
 * local state (fix queue, cached config/ETags, deviceId, DataStore) and return to sign-in"). Pure
 * Kotlin — no `android.*` import — so [PrivacyStateHolder] stays unit-testable without a real
 * `Context`.
 */
fun interface LocalStateWiper {
    suspend fun wipeAll(uid: String)
}

/**
 * The real [LocalStateWiper], wired by `AppContainer`. Only the fix queue and the per-uid
 * `deviceId` store are concrete, persisted client state in this codebase today — there is no
 * separate cached-config/ETag store or `androidx.datastore` usage anywhere yet (geofence ETags
 * live only in `GeofencesStateHolder`'s in-memory session state, already gone on process death;
 * `AppConfig` is a `BuildConfig` wrapper, not a persisted DataStore). This mirrors
 * [com.findly.android.queue.FixQueueStore]'s own documented deferral (specs/003 §10.4): a future
 * persisted cache/DataStore slots in here with zero call-site changes.
 */
class DefaultLocalStateWiper(
    private val fixQueueStore: FixQueueStore,
    private val deviceIdStore: DeviceIdStore,
) : LocalStateWiper {
    override suspend fun wipeAll(uid: String) {
        fixQueueStore.clearAll()
        deviceIdStore.clear(uid)
    }
}
