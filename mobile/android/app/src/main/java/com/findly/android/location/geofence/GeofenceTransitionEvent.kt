package com.findly.android.location.geofence

/** `"enter"`/`"exit"` (001-api-contract.md §7.3) — devices register and report both regardless of
 * a geofence's `notifyOnEnter`/`notifyOnExit` flags (specs/009-device-runtime.md §6.3: those
 * control server-side notification fan-out only). `DWELL` is never requested, so is not modeled
 * here. */
enum class GeofenceTransitionType {
    Enter,
    Exit,
    ;

    fun toWireValue(): String = when (this) {
        Enter -> "enter"
        Exit -> "exit"
    }
}

/**
 * The parsed, platform-independent shape of one `GeofencingClient` enter/exit callback (specs/009
 * §6.3) — [geofenceIds] because a single callback can report several geofences sharing the same
 * [transition] and the same [triggeringLocation][lat]/[lon] (Play services batches same-transition
 * geofences into one `GeofencingEvent`); there is exactly one location per callback, which is why
 * [com.findly.android.location.geofence.GeofenceTransitionHandler] queues one event **per**
 * geofence id but captures only **one** `source: "geofence"` fix per callback (§6.3: "additionally
 * capture one fix").
 */
data class GeofenceTransitionEvent(
    val geofenceIds: List<String>,
    val transition: GeofenceTransitionType,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
)
