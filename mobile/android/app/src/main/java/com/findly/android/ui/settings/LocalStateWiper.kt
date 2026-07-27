package com.findly.android.ui.settings

import com.findly.android.device.DeviceIdStore
import com.findly.android.location.settings.GeofenceConfigStateStore
import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.GeofenceEventQueueStore

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
 * the export artifact directory (specs/008 §3.1), and — as of A11 — the durable geofence-event
 * queue and the cached geofence config document/ETag (specs/009-device-runtime.md §6.1). The
 * "any cached config/ETags" wording this class's doc has always quoted had nothing concrete to
 * wire until [GeofenceConfigStateStore] landed; a plaintext cache of a family's configured
 * geofence names/coordinates must not outlive the account it belongs to, same reasoning as the
 * export-artifact rule right above it.
 */
class DefaultLocalStateWiper(
    private val fixQueueStore: FixQueueStore,
    private val deviceIdStore: DeviceIdStore,
    private val exportArtifactCleaner: ExportArtifactCleaner,
    private val geofenceEventQueueStore: GeofenceEventQueueStore,
    private val geofenceConfigStateStore: GeofenceConfigStateStore,
) : LocalStateWiper {
    override suspend fun wipeAll(uid: String) {
        fixQueueStore.clearAll()
        deviceIdStore.clear(uid)
        exportArtifactCleaner.clear()
        geofenceEventQueueStore.clearAll()
        geofenceConfigStateStore.clear()
    }
}
