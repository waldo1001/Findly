package com.findly.android.queue

import com.findly.android.network.dto.LocationFixDto

/** `"periodic"|"locate"|"geofence"|"manual"` (001-api-contract.md §5.1). */
enum class FixSource {
    Periodic,
    Locate,
    Geofence,
    Manual,
    ;

    fun toWireValue(): String = when (this) {
        Periodic -> "periodic"
        Locate -> "locate"
        Geofence -> "geofence"
        Manual -> "manual"
    }

    companion object {
        fun fromWireValue(value: String): FixSource = when (value) {
            "periodic" -> Periodic
            "locate" -> Locate
            "geofence" -> Geofence
            "manual" -> Manual
            else -> error("Unknown location fix source '$value'")
        }
    }
}

/** A single queued location fix awaiting upload (specs/003-android-client.md §10.1). */
data class QueuedFix(
    val fixId: String,
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val altitudeM: Double? = null,
    val speedMps: Double? = null,
    val bearingDeg: Double? = null,
    val batteryPct: Int,
    val source: FixSource,
)

fun QueuedFix.toDto(): LocationFixDto = LocationFixDto(
    fixId = fixId,
    recordedAt = recordedAt,
    lat = lat,
    lon = lon,
    accuracyM = accuracyM,
    altitudeM = altitudeM,
    speedMps = speedMps,
    bearingDeg = bearingDeg,
    batteryPct = batteryPct,
    source = source.toWireValue(),
)
