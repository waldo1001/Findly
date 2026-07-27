package com.findly.android.queue

import com.findly.android.network.dto.GeofenceEventInputDto

/** A single queued geofence transition event awaiting upload (001-api-contract.md §7.3;
 * specs/009-device-runtime.md §6.3). `transition` is the wire value directly (`"enter"`/`"exit"`)
 * — there is no client-side decision logic that needs a richer type here, unlike [FixSource]. */
data class QueuedGeofenceEvent(
    val eventId: String,
    val geofenceId: String,
    val transition: String,
    val recordedAt: String,
)

/** A frozen slice of pending events under a stable (client-local only — never sent over the wire,
 * 001 §7.3's request body has no `batchId` field) id, mirroring [FixBatch]'s freeze-on-first-ask
 * shape so a transient-failure retry resends the identical set (specs/009-device-runtime.md §6.3:
 * "Events are flushed like fixes"). */
data class GeofenceEventBatch(val batchId: String, val events: List<QueuedGeofenceEvent>)

fun QueuedGeofenceEvent.toDto(): GeofenceEventInputDto = GeofenceEventInputDto(
    eventId = eventId,
    geofenceId = geofenceId,
    transition = transition,
    recordedAt = recordedAt,
)
