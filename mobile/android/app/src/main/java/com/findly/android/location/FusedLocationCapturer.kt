package com.findly.android.location

import android.annotation.SuppressLint
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import java.time.Instant
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The real, `FusedLocationProviderClient`-backed [LocationCapturer] (specs/009-device-runtime.md
 * §1.1). Thin, untested Android-framework glue by design — no toolchain here to exercise a real
 * device/emulator GPS fix (same bucket as `AndroidDeviceInfoProvider`, specs/003-android-client.md
 * §3); all suppression/pipeline logic lives in the tested [FixCaptureCoordinator], and the
 * cached-position age arithmetic lives in the tested [CapturePolicy]. Never holds a continuous
 * stream: `getCurrentLocation` is FusedLocationProviderClient's one-shot "give me a single current
 * fix" API (as opposed to `requestLocationUpdates`, which this class never calls).
 * Reads [batteryLevelProvider] at capture time to fill [CapturedFix.batteryPct] — A9's
 * [CapturedFix] shape bakes battery in, so it's this class's job, not its callers'.
 *
 * A40 (specs/009 §1.1 "Accepting a recent cached position"): the one-shot request uses a
 * `CurrentLocationRequest` with [CapturePolicy.maxUpdateAgeMillisFor] so an already-computed
 * `BALANCED` position may satisfy it outright. If that request still comes back `null` — the
 * common background-capture failure mode — a `BALANCED` request (never `HIGH`: `locate`/`manual`
 * "exist to produce a fresh fix") falls back to [FusedLocationProviderClient.getLastLocation],
 * accepted only when [CapturePolicy.acceptsCachedFallback] says the position is young enough. The
 * fallback's `recordedAt` is always the platform location's own timestamp (`toCapturedFix`),
 * never the capture time — "so history stays honest" (§1.1).
 */
class FusedLocationCapturer(
    private val fusedLocationProviderClient: FusedLocationProviderClient,
    private val batteryLevelProvider: BatteryLevelProvider,
    private val now: () -> Instant = Instant::now,
) : LocationCapturer {

    @SuppressLint("MissingPermission") // the caller (FixCaptureCoordinator) already gates on permission (§1.2)
    override suspend fun captureFix(
        accuracy: LocationAccuracyTier,
        timeoutMillis: Long,
        maxCachedAgeMillis: Long,
    ): CapturedFix? {
        val priority = when (accuracy) {
            LocationAccuracyTier.BALANCED -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            LocationAccuracyTier.HIGH -> Priority.PRIORITY_HIGH_ACCURACY
        }
        val request = CurrentLocationRequest.Builder()
            .setPriority(priority)
            .setDurationMillis(timeoutMillis)
            .setMaxUpdateAgeMillis(CapturePolicy.maxUpdateAgeMillisFor(accuracy))
            .build()
        val cancellationTokenSource = CancellationTokenSource()

        val fresh = try {
            withTimeoutOrNull(timeoutMillis) {
                fusedLocationProviderClient
                    .getCurrentLocation(request, cancellationTokenSource.token)
                    .await()
            }
        } catch (e: Exception) {
            // §1.1: "no fix is better than a burned battery" - any failure is a silent null,
            // never an exception surfaced to the caller.
            null
        }
        if (fresh != null) return fresh.toCapturedFix(batteryLevelProvider.currentBatteryPct())
        cancellationTokenSource.cancel()

        return fallbackToLastLocationOrNull(accuracy, maxCachedAgeMillis)
    }

    @SuppressLint("MissingPermission")
    private suspend fun fallbackToLastLocationOrNull(
        accuracy: LocationAccuracyTier,
        maxCachedAgeMillis: Long,
    ): CapturedFix? {
        val last = try {
            fusedLocationProviderClient.lastLocation.await()
        } catch (e: Exception) {
            null
        } ?: return null

        val cachedAgeMillis = now().toEpochMilli() - last.time
        if (!CapturePolicy.acceptsCachedFallback(accuracy, cachedAgeMillis, maxCachedAgeMillis)) return null

        return last.toCapturedFix(batteryLevelProvider.currentBatteryPct())
    }
}

private fun android.location.Location.toCapturedFix(batteryPct: Int): CapturedFix = CapturedFix(
    lat = latitude,
    lon = longitude,
    accuracyM = accuracy.toDouble(),
    altitudeM = if (hasAltitude()) altitude else null,
    speedMps = if (hasSpeed()) speed.toDouble() else null,
    bearingDeg = if (hasBearing()) bearing.toDouble() else null,
    recordedAt = Instant.ofEpochMilli(time).toString(),
    batteryPct = batteryPct,
)
