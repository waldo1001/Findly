package com.findly.android.location.geofence

import android.annotation.SuppressLint
import android.app.PendingIntent
import com.findly.android.location.LocationPermissionState
import com.findly.android.location.settings.GeofenceRegistry
import com.findly.android.network.dto.GeofenceDto
import com.findly.android.pushmessages.GeofenceRegistrar
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * The real, `GeofencingClient`-backed [GeofenceRegistry]/[GeofenceRegistrar] (specs/009-device-
 * runtime.md §6.2) — one class implements both A9/A10's seams, as A10's own report predicted
 * ("A11 will also need to reconcile these... likely one real class implementing both").
 *
 * Registration is always a full replace, "unregister all, then register all", in that order
 * (this task's brief) — [registerAll] itself performs both halves internally via the same
 * [pendingIntent]/[geofencingClient], so every §6.2 trigger only ever needs to call `registerAll`.
 * **Non-atomicity is accepted, not a bug** (specs/009 §6.2, normative): if the process dies between
 * the unregister and the register call, the device is left with zero geofences — a real, reachable,
 * self-healing state (the next `geofenceEtag` mismatch re-triggers a full retry). No retry loop or
 * transaction is attempted here to "fix" that, matching the spec's own accepted-risk framing.
 *
 * [registerAll] is deliberately **not** suspend (the fixed [GeofenceRegistrar] shape, A9's "do not
 * change this shape without checking every caller") — the actual unregister+add sequence runs on
 * [scope] instead, fire-and-forget from the caller's point of view. Every caller already treats
 * config sync as best-effort (specs/009 §1/§5); [GeofenceConfigSyncCoordinator][com.findly.android.location.settings.GeofenceConfigSyncCoordinator]
 * doesn't wait for the platform call to settle before returning. [unregisterAll] **is** suspend
 * ([GeofenceRegistry]'s shape) and is awaited directly by pause
 * ([com.findly.android.location.settings.DeviceSettingsCoordinator]).
 *
 * Permission-gated per specs/009 §7 / the A11 task brief (mirrors how
 * [com.findly.android.location.FixCaptureCoordinator] checks [LocationPermissionState] before
 * capturing): [addGeofences][GeofencingClient.addGeofences] is skipped entirely — silently, no
 * exception — when background location isn't currently granted, since `GeofencingClient` cannot
 * reliably deliver transitions without it. `unregisterAll` has no such gate: removing a
 * registration is always safe to attempt regardless of current permission state.
 *
 * Thin, untested Android-framework glue by design (same bucket as `FusedLocationCapturer`/
 * `GoogleMapRenderer`) — all cap/cache/ETag decision logic lives in the tested
 * [com.findly.android.location.settings.GeofenceConfigSyncCoordinator], this class's one caller
 * for [registerAll].
 */
class GeofencingClientManager(
    private val geofencingClient: GeofencingClient,
    private val pendingIntent: PendingIntent,
    private val permissionState: LocationPermissionState,
    private val scope: CoroutineScope,
) : GeofenceRegistry, GeofenceRegistrar {

    override suspend fun unregisterAll() {
        try {
            geofencingClient.removeGeofences(pendingIntent).await()
        } catch (e: Exception) {
            // Best-effort, same silent-failure posture as every other specs/009 §6.2 step - a
            // failed removal is still bounded by the next full-replace trigger.
        }
    }

    @SuppressLint("MissingPermission") // permissionState is checked below before every add
    override fun registerAll(geofences: List<GeofenceDto>, etag: String) {
        scope.launch {
            unregisterAll()
            if (geofences.isEmpty()) return@launch
            if (!permissionState.isGranted()) return@launch
            try {
                geofencingClient.addGeofences(buildRequest(geofences), pendingIntent).await()
            } catch (e: Exception) {
                // Best-effort - the next geofenceEtag mismatch (§6.2) re-triggers a full retry.
            }
        }
    }

    private fun buildRequest(geofences: List<GeofenceDto>): GeofencingRequest =
        GeofencingRequest.Builder()
            .addGeofences(geofences.map { it.toPlatformGeofence() })
            .build()

    private fun GeofenceDto.toPlatformGeofence(): Geofence =
        Geofence.Builder()
            .setRequestId(geofenceId)
            .setCircularRegion(lat, lon, radiusM.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()
}
