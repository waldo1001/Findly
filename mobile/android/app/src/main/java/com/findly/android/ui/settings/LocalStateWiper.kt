package com.findly.android.ui.settings

import com.findly.android.device.DeviceIdStore
import com.findly.android.queue.FixQueueStore

/**
 * Wipes every piece of local client state after a successful account deletion
 * (specs/008-privacy-endpoints.md §4.4/§3.1; specs/003-android-client.md §12.4: "clear all local
 * state — fix queue, deviceId, any cached config/ETags, and the export artifacts of 008 §3.1 —
 * and return to sign-in"). Pure Kotlin — no `android.*` import — so [PrivacyStateHolder] stays
 * unit-testable without a real `Context`.
 */
fun interface LocalStateWiper {
    suspend fun wipeAll(uid: String)
}

/**
 * Deletes any export artifact (specs/008-privacy-endpoints.md §3.1 rule 2: "must also be removed
 * by the account-deletion local wipe"). Kept behind an interface — rather than [DefaultLocalStateWiper]
 * depending on [ExportFileWriter] directly — so this class stays pure Kotlin/JVM-testable;
 * `AppContainer` wires the real, `Context`-touching implementation
 * ([ExportFileWriter.clearArtifacts]).
 */
fun interface ExportArtifactCleaner {
    fun clear()
}

/**
 * The real [LocalStateWiper], wired by `AppContainer`. Covers every piece of concrete, persisted
 * client state that exists in this codebase today: the fix queue, the per-uid `deviceId` store,
 * and the export artifact directory (specs/008 §3.1). There is still no separate cached-
 * config/ETag store or `androidx.datastore` usage anywhere (geofence ETags live only in
 * `GeofencesStateHolder`'s in-memory session state, already gone on process death; `AppConfig` is
 * a `BuildConfig` wrapper, not a persisted DataStore) — this mirrors
 * [com.findly.android.queue.FixQueueStore]'s own documented deferral (specs/003 §10.4): a future
 * persisted cache/DataStore slots in here with zero call-site changes.
 */
class DefaultLocalStateWiper(
    private val fixQueueStore: FixQueueStore,
    private val deviceIdStore: DeviceIdStore,
    private val exportArtifactCleaner: ExportArtifactCleaner,
) : LocalStateWiper {
    override suspend fun wipeAll(uid: String) {
        fixQueueStore.clearAll()
        deviceIdStore.clear(uid)
        exportArtifactCleaner.clear()
    }
}
