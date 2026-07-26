package com.findly.android.pushmessages

import com.findly.android.location.LocationAccuracyTier
import com.findly.android.location.LocationCapturer
import com.findly.android.network.dto.FulfillFixDto
import com.findly.android.network.ports.LocateApi
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * `LOCATE_REQUEST` (001-api-contract.md §8.1; specs/009-device-runtime.md §5.1). On receipt: if
 * `now > expiresAt + 10 min`, ignore it silently (no GPS burn for a stale request); otherwise
 * capture one **high-accuracy** fix and `POST /locate-requests/{id}/fulfill` with
 * `source: "locate"` (§6.3). Deliberately takes no pause/tracking-enabled input — a paused device
 * still fulfills an explicit locate request (009 §5.1); only the periodic pipeline's own §1.2
 * suppression rules check pause state, and that check simply isn't wired into this class at all.
 *
 * A malformed payload (missing/invalid `requestId`/`expiresAt`) is dropped silently, never
 * crashed on (009 §5 intro). Failure to obtain a fix, or no signed-in device to fulfill as, is
 * also a silent give-up — "the requester's poll surfaces the outcome" (009 §5.1).
 */
class LocateRequestPushHandler(
    private val locationCapturer: LocationCapturer,
    private val locateApi: LocateApi,
    /** Resolves the current device's `deviceId`, or `null` if there is none to fulfill as
     * (signed out, never registered). Re-evaluated on every call, not captured once. */
    private val deviceIdProvider: () -> String?,
    private val fixIdGenerator: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> Instant = Instant::now,
) {
    suspend fun handle(data: Map<String, String>) {
        val requestId = data["requestId"]?.takeIf { it.isNotBlank() } ?: return
        val expiresAt = data["expiresAt"]?.let(::parseInstantOrNull) ?: return
        if (now().isAfter(expiresAt.plus(STALE_GRACE))) return

        val deviceId = deviceIdProvider() ?: return
        val fix = locationCapturer.captureFix(LocationAccuracyTier.HIGH) ?: return

        locateApi.fulfillLocateRequest(
            requestId = requestId,
            deviceId = deviceId,
            fix = FulfillFixDto(
                fixId = fixIdGenerator(),
                recordedAt = fix.recordedAt,
                lat = fix.lat,
                lon = fix.lon,
                accuracyM = fix.accuracyM,
                altitudeM = fix.altitudeM,
                speedMps = fix.speedMps,
                bearingDeg = fix.bearingDeg,
                batteryPct = fix.batteryPct,
                source = "locate",
            ),
        )
        // Result intentionally ignored - a failed fulfill call is silent per 009 §5.1.
    }

    private fun parseInstantOrNull(iso: String): Instant? = try {
        Instant.parse(iso)
    } catch (e: Exception) {
        null
    }

    private companion object {
        val STALE_GRACE: Duration = Duration.ofMinutes(10)
    }
}
