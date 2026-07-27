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
 * so this seam has no pause check of its own; callers that DO need suppression (periodic capture)
 * apply it themselves before calling this — see [com.findly.android.location.FixCaptureCoordinator]
 * (A10).
 *
 * [timeoutMillis] defaults to 30 s (§1.1's value for `HIGH`/`locate`-`manual` and `periodic`'s
 * `BALANCED` request) — [com.findly.android.pushmessages.LocateRequestPushHandler] (A9) calls
 * `captureFix(LocationAccuracyTier.HIGH)` without overriding it, which is exactly §1.1's `locate`
 * timeout. Only the `geofence` trigger's `BALANCED` request needs the shorter 15 s (§6.3), passed
 * explicitly by [FixCaptureCoordinator] — `LocationAccuracyTier` alone can't distinguish
 * `periodic`'s and `geofence`'s both-`BALANCED` requests, so the timeout has to travel
 * separately. Do not change this shape without checking every caller.
 *
 * [FusedLocationCapturer] is the real, `FusedLocationProviderClient`-backed implementation (A10).
 */
fun interface LocationCapturer {
    suspend fun captureFix(accuracy: LocationAccuracyTier, timeoutMillis: Long = 30_000L): CapturedFix?
}

/** A9's placeholder wiring target (`AppContainer`) until A10 lands the real implementation above —
 * always "no fix obtainable", which every §1.1 trigger's own contract already treats as a safe,
 * silent give-up (009 §5.1: "give up silently"). */
object UnimplementedLocationCapturer : LocationCapturer {
    override suspend fun captureFix(accuracy: LocationAccuracyTier, timeoutMillis: Long): CapturedFix? = null
}
