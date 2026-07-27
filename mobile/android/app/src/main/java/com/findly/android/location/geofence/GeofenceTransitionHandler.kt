package com.findly.android.location.geofence

import com.findly.android.location.BatteryLevelProvider
import com.findly.android.location.CapturedFix
import com.findly.android.location.FixCaptureCoordinator
import com.findly.android.location.TrackingPauseState
import com.findly.android.queue.FixSource
import com.findly.android.queue.GeofenceEventQueueStore
import com.findly.android.queue.QueuedGeofenceEvent
import java.time.Instant
import java.util.UUID

/**
 * The tested decision/coordination logic behind a `GeofencingClient` enter/exit callback
 * (specs/009-device-runtime.md §6.3) — deliberately separated from [GeofenceTransitionReceiver]
 * (the untested `BroadcastReceiver` glue) so this class needs no `Context`/`GeofencingEvent`/
 * Robolectric at all, matching the seam split A10 already established for
 * [com.findly.android.location.FixCaptureCoordinator] vs. `FusedLocationCapturer`.
 *
 * Per specs/009 §4: "Transitions detected while paused are dropped, not queued" — a safety net for
 * the race where a callback was already in flight when pause called
 * [com.findly.android.location.settings.GeofenceRegistry.unregisterAll]; the normal case is that
 * pause already removed every platform registration, so no callback fires at all. This check has
 * to happen here (not just inside [fixCaptureCoordinator], whose own pause check only guards the
 * fix) because it must also gate the geofence-event enqueue, which bypasses
 * [FixCaptureCoordinator] entirely.
 */
class GeofenceTransitionHandler(
    private val eventQueueStore: GeofenceEventQueueStore,
    private val fixCaptureCoordinator: FixCaptureCoordinator,
    private val batteryLevelProvider: BatteryLevelProvider,
    private val pauseState: TrackingPauseState,
    private val eventIdGenerator: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> Instant = Instant::now,
) {
    suspend fun handle(event: GeofenceTransitionEvent) {
        if (pauseState.isPaused()) return

        val recordedAt = now().toString()
        event.geofenceIds.forEach { geofenceId ->
            eventQueueStore.enqueue(
                QueuedGeofenceEvent(
                    eventId = eventIdGenerator(),
                    geofenceId = geofenceId,
                    transition = event.transition.toWireValue(),
                    recordedAt = recordedAt,
                ),
            )
        }

        // specs/009 §6.3: "additionally capture one fix with source: geofence... MAY reuse the
        // transition's own coordinates" - one fix per callback, not per triggering geofence id.
        fixCaptureCoordinator.captureAndQueue(
            FixSource.Geofence,
            hint = CapturedFix(
                recordedAt = recordedAt,
                lat = event.lat,
                lon = event.lon,
                accuracyM = event.accuracyM,
                batteryPct = batteryLevelProvider.currentBatteryPct(),
            ),
        )
    }
}
