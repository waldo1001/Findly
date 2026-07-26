package com.findly.android.location

/** Accuracy tier requested for a single fix capture (specs/009-device-runtime.md §1.1's
 * "Accuracy request" column) — `HIGH` (best available) for the `locate`/`manual` sources,
 * `BALANCED` (~100 m, never continuous GPS) for `periodic`/`geofence`. */
enum class LocationAccuracyTier { HIGH, BALANCED }

/** The GPS-observed fields of one location fix — deliberately excludes `fixId`/`source`
 * (001-api-contract.md §5.1): those are assigned by the caller building the wire DTO (a
 * client-generated UUID and the trigger that caused the capture, respectively), not by capture
 * itself, so this shape is reusable across every 009 §1.1 trigger without embedding
 * upload-specific concerns. */
data class CapturedFix(
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val altitudeM: Double? = null,
    val speedMps: Double? = null,
    val bearingDeg: Double? = null,
    val batteryPct: Int,
)

/**
 * Seam for one-shot location capture, deliberately decoupled from the periodic queue pipeline
 * (`queue/FixQueueStore`) and its pause/permission suppression rules (specs/009-device-runtime.md
 * §1.2) — a `LOCATE_REQUEST` push (009 §5.1) MUST capture a fix even while the device is paused,
 * so this seam has no pause check of its own; callers that DO need suppression (periodic capture,
 * A10) are expected to apply it themselves before calling this.
 *
 * No production implementation exists yet. A10 (specs/009-device-runtime.md §1) owns the real
 * `FusedLocationProviderClient`-backed one, respecting the §1.1 timeout table (30 s for
 * `HIGH`/`locate`-`manual`, 15 s for the `geofence` trigger's `BALANCED` request, 30 s for
 * `periodic`'s `BALANCED` request). [com.findly.android.pushmessages.LocateRequestPushHandler] is
 * this seam's first caller — do not change this shape without checking every caller.
 */
fun interface LocationCapturer {
    suspend fun captureFix(accuracy: LocationAccuracyTier): CapturedFix?
}

/** A9's placeholder wiring target (`AppContainer`) until A10 lands the real implementation above —
 * always "no fix obtainable", which every §1.1 trigger's own contract already treats as a safe,
 * silent give-up (009 §5.1: "give up silently"). */
object UnimplementedLocationCapturer : LocationCapturer {
    override suspend fun captureFix(accuracy: LocationAccuracyTier): CapturedFix? = null
}
