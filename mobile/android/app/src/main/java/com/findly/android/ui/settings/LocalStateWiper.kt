package com.findly.android.ui.settings

import com.findly.android.device.DeviceIdStore
import com.findly.android.location.PermissionDisclosureStore
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
 * the export artifact directory (specs/008 §3.1), the durable geofence-event queue and the cached
 * geofence config document/ETag (specs/009-device-runtime.md §6.1, A11), and — as of A25 — the
 * permission-disclosure acknowledgement/decline flags (specs/009 §7). The "any cached config/
 * ETags" wording this class's doc has always quoted had nothing concrete to wire until
 * [GeofenceConfigStateStore] landed; a plaintext cache of a family's configured geofence names/
 * coordinates must not outlive the account it belongs to, same reasoning as the export-artifact
 * rule right above it.
 *
 * **Code-review fix (A25 round 1, Major 2): [permissionDisclosureStore] was documented as part of
 * the account-deletion wipe (this task's own spec commit: "a different user on the same device
 * MUST see the disclosure again") but had no caller anywhere in production code** — the same shape
 * of mistake as the iOS I26 finding ("a documented clear that nothing calls"). Wired in here so the
 * documented behaviour and the actual behaviour agree.
 *
 * Security-review fix (post-A11 review): each step runs independently of the others'
 * success/failure ([runCatching], swallowing only the exception itself — nothing sensitive is
 * logged). Unguarded sequential suspend calls meant one throwing (e.g. a Room `deleteAll()`
 * disk I/O error) silently skipped every step after it — worst case, the geofence config cache
 * (the most sensitive of the local stores: a family's named places) could survive an account
 * deletion that otherwise appeared to complete. Reordering alone would not have fixed this — a
 * failure anywhere still skips everything *after* it, wherever "after" is — so every step is
 * wrapped, not just reordered.
 */
class DefaultLocalStateWiper(
    private val fixQueueStore: FixQueueStore,
    private val deviceIdStore: DeviceIdStore,
    private val exportArtifactCleaner: ExportArtifactCleaner,
    private val geofenceEventQueueStore: GeofenceEventQueueStore,
    private val geofenceConfigStateStore: GeofenceConfigStateStore,
    private val permissionDisclosureStore: PermissionDisclosureStore,
) : LocalStateWiper {
    override suspend fun wipeAll(uid: String) {
        runCatching { fixQueueStore.clearAll() }
        runCatching { deviceIdStore.clear(uid) }
        runCatching { exportArtifactCleaner.clear() }
        runCatching { geofenceEventQueueStore.clearAll() }
        runCatching { geofenceConfigStateStore.clear() }
        runCatching { permissionDisclosureStore.clear() }
    }
}
